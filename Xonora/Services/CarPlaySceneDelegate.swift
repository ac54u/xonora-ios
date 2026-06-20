import CarPlay
import MediaPlayer
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private let playerManager = PlayerManager.shared
    private let libraryViewModel = LibraryViewModel.shared
    private let client = XonoraClient.shared

    // Template cache to avoid recreating templates on every drill-down
    private var templateCache = NSCache<NSString, CPTemplate>()
    private let albumsCacheKey = "albums-list" as NSString
    private let playlistsCacheKey = "playlists-list" as NSString
    private let artistsCacheKey = "artists-list" as NSString
    private let nowPlayingKey = "now-playing" as NSString
    private let queueKey = "queue" as NSString

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        setupNowPlayingObservers()

        let rootTemplates = buildTabBarTemplates()
        let tabBarTemplate = CPTabBarTemplate(templates: rootTemplates)
        interfaceController.setRootTemplate(tabBarTemplate, animated: true, completion: nil)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }

    // MARK: - Tab Bar

    private func buildTabBarTemplates() -> [CPTemplate] {
        let libraryTab = buildLibraryTab()
        let nowPlayingTab = buildNowPlayingTab()
        let queueTab = buildQueueTab()

        return [libraryTab, nowPlayingTab, queueTab]
    }

    private func makeLibraryItem(title: String, subtitle: String, icon: String, handler: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(
            text: NSLocalizedString(title, comment: "CarPlay \(title)"),
            detailText: NSLocalizedString(subtitle, comment: "CarPlay \(title) description"),
            image: UIImage(systemName: icon)
        )
        item.handler = { _, completion in
            handler()
            completion()
        }
        return item
    }

    // MARK: - Library Tab

    private func buildLibraryTab() -> CPTemplate {
        let items = [
            makeLibraryItem(title: "Albums", subtitle: "Browse your album collection", icon: "rectangle.stack.fill") { [weak self] in
                self?.showAlbums()
            },
            makeLibraryItem(title: "Artists", subtitle: "Browse by artist", icon: "person.2.fill") { [weak self] in
                self?.showArtists()
            },
            makeLibraryItem(title: "Playlists", subtitle: "Your custom collections", icon: "music.note.list") { [weak self] in
                self?.showPlaylists()
            },
            makeLibraryItem(title: "Songs", subtitle: "All tracks", icon: "music.note") { [weak self] in
                self?.showSongs()
            }
        ]

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: NSLocalizedString("Library", comment: "CarPlay library title"), sections: [section])
        return template
    }

    // MARK: - Now Playing Tab

    private func buildNowPlayingTab() -> CPTemplate {
        if let cached = templateCache.object(forKey: nowPlayingKey) {
            return cached
        }

        let template = CPNowPlayingTemplate.shared
        template.upNextTitle = NSLocalizedString("Queue", comment: "CarPlay queue title")
        setupRemoteCommands()

        templateCache.setObject(template, forKey: nowPlayingKey)
        return template
    }

    private func updateNowPlayingTitles() {
        // CPNowPlayingTemplate updates labels automatically based on MPNowPlayingInfoCenter
    }

    private func setupRemoteCommands() {
        let cmd = MPRemoteCommandCenter.shared()
        cmd.changeShuffleModeCommand.isEnabled = true
        cmd.changeShuffleModeCommand.addTarget { [weak self] _ in
            self?.playerManager.toggleShuffle()
            return .success
        }
        cmd.changeRepeatModeCommand.isEnabled = true
        cmd.changeRepeatModeCommand.addTarget { [weak self] _ in
            self?.playerManager.cycleRepeatMode()
            return .success
        }
    }

    // MARK: - Queue Tab

    private func buildQueueTab() -> CPTemplate {
        if let cached = templateCache.object(forKey: queueKey) as? CPListTemplate {
            return cached
        }

        let template = CPListTemplate(title: NSLocalizedString("Queue", comment: "CarPlay queue"), sections: [])
        template.emptyViewSubtitleVariants = [NSLocalizedString("Queue is empty", comment: "CarPlay empty queue")]
        templateCache.setObject(template, forKey: queueKey)
        return template
    }

    private func refreshQueueTab() {
        guard let interfaceController = interfaceController,
              let tabBar = interfaceController.rootTemplate as? CPTabBarTemplate else { return }

        let queueItems = playerManager.queue.enumerated().map { index, track -> CPListItem in
            let item = CPListItem(
                text: track.name,
                detailText: track.artistNames
            )
            item.handler = { [weak self] _, completion in
                self?.playerManager.playTrack(track)
                completion()
            }
            item.isPlaying = index == playerManager.currentIndex
            return item
        }

        let template = CPListTemplate(
            title: NSLocalizedString("Queue", comment: "CarPlay queue"),
            sections: queueItems.isEmpty ? [] : [CPListSection(items: queueItems)]
        )
        template.emptyViewSubtitleVariants = [NSLocalizedString("Queue is empty", comment: "CarPlay empty queue")]

        templateCache.setObject(template, forKey: queueKey)

        // Update the tab if visible
        if let current = interfaceController.topTemplate as? CPListTemplate,
           current.title == NSLocalizedString("Queue", comment: "CarPlay queue") {
            interfaceController.popTemplate(animated: false) { _, _ in
                interfaceController.pushTemplate(template, animated: false, completion: nil)
            }
        }
    }

    // MARK: - Library Browsing

    private func showAlbums() {
        let cachedKey = "albums" as NSString
        if let cached = templateCache.object(forKey: cachedKey) {
            interfaceController?.pushTemplate(cached, animated: true, completion: nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let albums = self.libraryViewModel.albums
            let items = albums.map { album -> CPListItem in
                let item = CPListItem(text: album.name, detailText: album.artistNames)
                item.handler = { [weak self] _, completion in
                    self?.showAlbumTracks(album)
                    completion()
                }
                return item
            }

            let section = CPListSection(items: items)
            let template = CPListTemplate(title: NSLocalizedString("Albums", comment: "CarPlay albums"), sections: [section])
            self.templateCache.setObject(template, forKey: cachedKey)
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showAlbumTracks(_ album: Album) {
        let cachedKey = "album-\(album.itemId)" as NSString
        if let cached = templateCache.object(forKey: cachedKey) {
            interfaceController?.pushTemplate(cached, animated: true, completion: nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let tracks = try await self.libraryViewModel.loadAlbumTracks(album: album)
                let items = tracks.map { track -> CPListItem in
                    let item = CPListItem(text: track.name, detailText: track.artistNames)
                    item.handler = { [weak self] _, completion in
                        self?.playerManager.playAlbum(tracks)
                        self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                        completion()
                    }
                    return item
                }

                let section = CPListSection(items: items)
                let template = CPListTemplate(title: album.name, sections: [section])
                self.templateCache.setObject(template, forKey: cachedKey)
                self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("[CarPlay] Failed to load album tracks: \(error)")
            }
        }
    }

    private func showArtists() {
        let cachedKey = "artists" as NSString
        if let cached = templateCache.object(forKey: cachedKey) {
            interfaceController?.pushTemplate(cached, animated: true, completion: nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let artists = self.libraryViewModel.artists
            let items = artists.map { artist -> CPListItem in
                let item = CPListItem(text: artist.name, detailText: nil)
                item.handler = { [weak self] _, completion in
                    self?.showArtistDetails(artist)
                    completion()
                }
                return item
            }

            let section = CPListSection(items: items)
            let template = CPListTemplate(title: NSLocalizedString("Artists", comment: "CarPlay artists"), sections: [section])
            self.templateCache.setObject(template, forKey: cachedKey)
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showArtistDetails(_ artist: Artist) {
        let cachedKey = "artist-\(artist.itemId)" as NSString
        if let cached = templateCache.object(forKey: cachedKey) {
            interfaceController?.pushTemplate(cached, animated: true, completion: nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let (albums, tracks) = try await self.libraryViewModel.loadArtistDetails(artist: artist)

                var sections: [CPListSection] = []

                if !tracks.isEmpty {
                    let trackItems = tracks.prefix(5).map { track -> CPListItem in
                        let item = CPListItem(text: track.name, detailText: track.artistNames)
                        item.handler = { [weak self] _, completion in
                            self?.playerManager.playTrack(track, fromQueue: Array(tracks), sourceName: artist.name)
                            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                            completion()
                        }
                        return item
                    }
                    sections.append(CPListSection(items: Array(trackItems), header: NSLocalizedString("Top Songs", comment: "CarPlay top songs"), sectionIndexTitle: nil))
                }

                if !albums.isEmpty {
                    let albumItems = albums.map { album -> CPListItem in
                        let item = CPListItem(text: album.name, detailText: String(album.year ?? 0))
                        item.handler = { [weak self] _, completion in
                            self?.showAlbumTracks(album)
                            completion()
                        }
                        return item
                    }
                    sections.append(CPListSection(items: Array(albumItems), header: NSLocalizedString("Albums", comment: "CarPlay albums"), sectionIndexTitle: nil))
                }

                let template = CPListTemplate(title: artist.name, sections: sections)
                self.templateCache.setObject(template, forKey: cachedKey)
                self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("[CarPlay] Failed to load artist details: \(error)")
            }
        }
    }

    private func showPlaylists() {
        let cachedKey = "playlists" as NSString
        if let cached = templateCache.object(forKey: cachedKey) {
            interfaceController?.pushTemplate(cached, animated: true, completion: nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let playlists = self.libraryViewModel.playlists
            let items = playlists.map { playlist -> CPListItem in
                let item = CPListItem(text: playlist.name, detailText: NSLocalizedString("Playlist", comment: "CarPlay playlist"))
                item.handler = { [weak self] _, completion in
                    self?.showPlaylistTracks(playlist)
                    completion()
                }
                return item
            }

            let section = CPListSection(items: items)
            let template = CPListTemplate(title: NSLocalizedString("Playlists", comment: "CarPlay playlists"), sections: [section])
            self.templateCache.setObject(template, forKey: cachedKey)
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showPlaylistTracks(_ playlist: Playlist) {
        let cachedKey = "playlist-\(playlist.itemId)" as NSString
        if let cached = templateCache.object(forKey: cachedKey) {
            interfaceController?.pushTemplate(cached, animated: true, completion: nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let tracks = try await self.libraryViewModel.loadPlaylistTracks(playlist: playlist)
                let items = tracks.map { track -> CPListItem in
                    let item = CPListItem(text: track.name, detailText: track.artistNames)
                    item.handler = { [weak self] _, completion in
                        self?.playerManager.playAlbum(tracks)
                        self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                        completion()
                    }
                    return item
                }

                let section = CPListSection(items: items)
                let template = CPListTemplate(title: playlist.name, sections: [section])
                self.templateCache.setObject(template, forKey: cachedKey)
                self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("[CarPlay] Failed to load playlist tracks: \(error)")
            }
        }
    }

    private func showSongs() {
        let cachedKey = "songs" as NSString
        if let cached = templateCache.object(forKey: cachedKey) {
            interfaceController?.pushTemplate(cached, animated: true, completion: nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let tracks = self.libraryViewModel.tracks
            let items = tracks.map { track -> CPListItem in
                let item = CPListItem(text: track.name, detailText: track.artistNames)
                item.handler = { [weak self] _, completion in
                    self?.playerManager.playTrack(track, fromQueue: tracks, sourceName: "Songs")
                    self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                    completion()
                }
                return item
            }

            let section = CPListSection(items: items)
            let template = CPListTemplate(title: NSLocalizedString("Songs", comment: "CarPlay songs"), sections: [section])
            self.templateCache.setObject(template, forKey: cachedKey)
            self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    // MARK: - Queue

    private func showQueue() {
        let template: CPListTemplate
        if let cached = templateCache.object(forKey: queueKey) as? CPListTemplate {
            // Update cache
            refreshQueueTab()
            template = cached
        } else {
            template = buildQueueTab() as! CPListTemplate
        }
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Now Playing Observers

    private func setupNowPlayingObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueDidUpdate),
            name: .queueUpdated,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateDidChange),
            name: .playbackStateChanged,
            object: nil
        )
    }

    @objc private func queueDidUpdate(_ notification: Notification) {
        refreshQueueTab()
    }

    @objc private func playbackStateDidChange(_ notification: Notification) {
        // Update now playing info via MPNowPlayingInfoCenter
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let playbackStateChanged = Notification.Name("playbackStateChanged")
}
