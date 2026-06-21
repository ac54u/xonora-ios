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
            // Mirror into the synchronous tier so views render it flash-free.
            SyncImageMemoryCache.shared.set(image, for: url)
            return image
        }
        return nil
    }

    func setImage(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        let data = image.jpegData(compressionQuality: 0.9) ?? image.pngData()
        cache.setObject(image, forKey: key, cost: data?.count ?? 0)
        // Mirror into the synchronous tier. This is the key to the flash-free Now
        // Playing artwork: the lock-screen artwork load (PlayerManager) calls
        // setImage with the same .medium URL the Now Playing view uses, so by the
        // time the page opens the image is already synchronously available.
        SyncImageMemoryCache.shared.set(image, for: url)
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

    // NOT seeded from sync cache in init — when `url` changes, `@State` retains
    // the previous track's image so we keep showing it while the new one loads,
    // eliminating the gray-placeholder flash on play/pause/next/prev.
    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let url = url, let cached = SyncImageMemoryCache.shared.image(for: url) {
                // Current URL is already cached — show it immediately,
                // overriding any stale image from a previous track.
                Image(uiImage: cached)
                    .resizable()
            } else if let image = image {
                // Keep showing the previous track's image while the new one
                // downloads, rather than flashing to the gray placeholder.
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url = url else { return }

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
