import Foundation
import SwiftUI

/// Two-tier image cache: fast in-memory NSCache backed by a persistent on-disk
/// cache. The disk tier survives app relaunches so album artwork no longer
/// reloads every time the app is opened.
actor ImageCache {
    static let shared = ImageCache()

    private var cache = NSCache<NSString, UIImage>()
    private var downloadingURLs = Set<String>()
    private let urlSession: URLSession
    private let diskURL: URL
    private let fileManager = FileManager.default

    private init() {
        cache.countLimit = 200 // Max images held in memory
        cache.totalCostLimit = 80 * 1024 * 1024 // 80MB max in memory

        // Reuse single URLSession to avoid reporter disconnection errors
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)

        // Persistent on-disk cache directory
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.diskURL = caches.appendingPathComponent("XonoraImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskURL, withIntermediateDirectories: true)
    }

    /// Stable FNV-1a hash so the same URL maps to the same file across launches
    /// (Swift's `hashValue` is randomized per process and cannot be used here).
    private func diskFileURL(for url: URL) -> URL {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return diskURL.appendingPathComponent(String(hash, radix: 16))
    }

    /// Look up the image in memory first, then fall back to disk (promoting it
    /// into memory on a hit).
    func image(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let fileURL = diskFileURL(for: url)
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            cache.setObject(image, forKey: key, cost: data.count)
            return image
        }
        return nil
    }

    func setImage(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        let data = image.jpegData(compressionQuality: 0.9) ?? image.pngData()
        cache.setObject(image, forKey: key, cost: data?.count ?? 0)
        if let data = data {
            try? data.write(to: diskFileURL(for: url), options: .atomic)
        }
    }

    func isDownloading(_ url: URL) -> Bool {
        downloadingURLs.contains(url.absoluteString)
    }

    func startDownloading(_ url: URL) {
        downloadingURLs.insert(url.absoluteString)
    }

    func finishDownloading(_ url: URL) {
        downloadingURLs.remove(url.absoluteString)
    }

    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: diskURL)
        try? fileManager.createDirectory(at: diskURL, withIntermediateDirectories: true)
    }

    var session: URLSession {
        urlSession
    }
}

/// A synchronous, thread-safe in-memory image cache. Lets a view render an
/// already-loaded image on its very first frame (no async actor hop), which is
/// what removes the gray-placeholder flash when switching tabs or toggling
/// play/pause causes the view to re-create.
final class SyncImageMemoryCache {
    static let shared = SyncImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 250
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func set(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString)
    }
}

/// A view that displays an image from a URL with caching support.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        // Seed from the synchronous memory cache so warm artwork shows on the first
        // frame — no placeholder flash on tab switch / play-pause re-render.
        _image = State(initialValue: url.flatMap { SyncImageMemoryCache.shared.image(for: $0) })
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder()
            }
        }
        // `.task(id:)` re-runs whenever `url` changes and auto-cancels the prior
        // load — this replaces the fragile onAppear/onChange combination that
        // could leave stale artwork or never fire when the URL went nil→value.
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url = url else {
            // No artwork for this item — drop any previous image so we show the
            // placeholder instead of the last track's cover.
            image = nil
            return
        }

        // Fast synchronous memory hit — no flash, no await.
        if let mem = SyncImageMemoryCache.shared.image(for: url) {
            if image !== mem { image = mem }
            return
        }

        // Disk/actor cache hit.
        if let cached = await ImageCache.shared.image(for: url) {
            SyncImageMemoryCache.shared.set(cached, for: url)
            image = cached
            return
        }

        // Cache miss: keep showing the previous image (if any) while the new one
        // downloads, rather than flashing to the gray placeholder. This kills the
        // "gray square on play/pause" flicker; the image is swapped in atomically
        // once the download completes.
        guard await !ImageCache.shared.isDownloading(url) else { return }
        await ImageCache.shared.startDownloading(url)
        defer { Task { await ImageCache.shared.finishDownloading(url) } }

        do {
            let session = await ImageCache.shared.session
            let (data, response) = try await session.data(from: url)

            if Task.isCancelled { return }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                safeLog("[ImageCache] Error loading image from \(url.absoluteString): HTTP \(httpResponse.statusCode)")
                return
            }

            if let downloadedImage = UIImage(data: data) {
                SyncImageMemoryCache.shared.set(downloadedImage, for: url)
                await ImageCache.shared.setImage(downloadedImage, for: url)
                if !Task.isCancelled && self.url == url {
                    image = downloadedImage
                }
            } else {
                safeLog("[ImageCache] Failed to decode image data from \(url.absoluteString)")
            }
        } catch {
            safeLog("[ImageCache] Exception loading image from \(url.absoluteString): \(error.localizedDescription)")
        }
    }

    private func safeLog(_ message: String) {
        // Truncate extremely long messages to avoid system logging issues (decode: bad range)
        // especially important for base64 data: URLs
        let logMessage = message.count > 1000 ? String(message.prefix(1000)) + "... (truncated)" : message
        print(logMessage)
    }
}

/// Convenience extension for common placeholder styles
extension CachedAsyncImage where Placeholder == Color {
    init(url: URL?) {
        self.init(url: url) {
            Color.gray.opacity(0.3)
        }
    }
}
