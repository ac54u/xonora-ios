import Foundation
import Combine

enum LibrarySortOption: String, CaseIterable {
    case name = "Name"
    case artist = "Artist"
    case year = "Year"
    case recentlyAdded = "Recently Added"

    var localizedName: String {
        NSLocalizedString(self.rawValue, comment: "Sort option")
    }
}

enum LibraryViewMode: String {
    case grid = "Grid"
    case list = "List"
}

@MainActor
class LibraryViewModel: ObservableObject {
    static let shared = LibraryViewModel()

    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var playlists: [Playlist] = []
    @Published var tracks: [Track] = []
    @Published var podcasts: [Podcast] = []
    @Published var radioStations: [RadioStation] = []
    @Published var lyrics: LyricsResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var searchResults: (albums: [Album], artists: [Artist], tracks: [Track]) = ([], [], [])
    @Published var isSearching = false

    // Pagination state
    @Published var albumTotal: Int = 0
    @Published var songTotal: Int = 0
    @Published var playlistTotal: Int = 0
    @Published var artistTotal: Int = 0
    @Published var isLoadingMoreAlbums = false
    @Published var isLoadingMoreSongs = false
    @Published var isLoadingMorePlaylists = false
    @Published var isLoadingMoreArtists = false
    @Published var podcastTotal: Int = 0
    @Published var radioTotal: Int = 0
    @Published var isLoadingMorePodcasts = false
    @Published var isLoadingMoreRadio = false

    private let pageSize = 200

    // Sort & view mode preferences per category
    @Published var albumSort: LibrarySortOption = .name
    @Published var albumViewMode: LibraryViewMode = .grid
    @Published var songSort: LibrarySortOption = .name
    @Published var playlistSort: LibrarySortOption = .name
    @Published var playlistViewMode: LibraryViewMode = .grid
    @Published var artistSort: LibrarySortOption = .name

    private var isNetworkFetching = false

    private let client = XonoraClient.shared
    private let cache = MetadataCache.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private let searchQueue = DispatchQueue(label: "com.musicassistant.search", qos: .userInitiated)
    private let loadQueue = DispatchQueue(label: "com.musicassistant.library", qos: .utility)

    private let defaults = UserDefaults.standard

    init() {
        loadSortPreferences()
        setupSearchDebounce()
    }

    private func loadSortPreferences() {
        if let raw = defaults.string(forKey: "albumSort"), let option = LibrarySortOption(rawValue: raw) {
            albumSort = option
        }
        if let raw = defaults.string(forKey: "albumViewMode"), let mode = LibraryViewMode(rawValue: raw) {
            albumViewMode = mode
        }
        if let raw = defaults.string(forKey: "songSort"), let option = LibrarySortOption(rawValue: raw) {
            songSort = option
        }
        if let raw = defaults.string(forKey: "playlistSort"), let option = LibrarySortOption(rawValue: raw) {
            playlistSort = option
        }
        if let raw = defaults.string(forKey: "playlistViewMode"), let mode = LibraryViewMode(rawValue: raw) {
            playlistViewMode = mode
        }
        if let raw = defaults.string(forKey: "artistSort"), let option = LibrarySortOption(rawValue: raw) {
            artistSort = option
        }
    }

    private func saveSortPreferences() {
        defaults.set(albumSort.rawValue, forKey: "albumSort")
        defaults.set(albumViewMode.rawValue, forKey: "albumViewMode")
        defaults.set(songSort.rawValue, forKey: "songSort")
        defaults.set(playlistSort.rawValue, forKey: "playlistSort")
        defaults.set(playlistViewMode.rawValue, forKey: "playlistViewMode")
        defaults.set(artistSort.rawValue, forKey: "artistSort")
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.isEmpty {
                    Task {
                        self.searchResults = ([], [], [])
                        self.isSearching = false
                    }
                } else {
                    Task {
                        await self.performSearch(query)
                    }
                }
            }
            .store(in: &cancellables)
    }

    func loadLibrary(forceRefresh: Bool = false) async {
        // 1. Load from cache first (Stale-while-revalidate)
        if !forceRefresh {
            let cachedAlbums = await cache.getAlbums()
            let cachedArtists = await cache.getArtists()
            let cachedPlaylists = await cache.getPlaylists()
            let cachedTracks = await cache.getTracks()

            if let albums = cachedAlbums, let artists = cachedArtists,
               let playlists = cachedPlaylists, let tracks = cachedTracks {
                self.albums = albums
                self.artists = artists
                self.playlists = playlists
                self.tracks = tracks
                print("[LibraryViewModel] Loaded from cache")
            }
        }

        // 2. Fetch from server
        guard !isNetworkFetching else { return }
        isNetworkFetching = true
        
        if albums.isEmpty {
            isLoading = true
        }

        if !forceRefresh {
            if let cachedPodcasts = await cache.getPodcasts() { self.podcasts = cachedPodcasts }
            if let cachedRadio = await cache.getRadioStations() { self.radioStations = cachedRadio }
        }

        errorMessage = nil

        do {
            async let albumsTask = client.fetchAlbums(limit: pageSize)
            async let artistsTask = client.fetchArtists(limit: pageSize)
            async let playlistsTask = client.fetchPlaylists(limit: pageSize)
            async let tracksTask = client.fetchTracks(limit: pageSize)
            async let podcastsTask = client.fetchPodcasts(limit: pageSize)
            async let radioTask = client.fetchRadioStations(limit: pageSize)

            let (fetchedAlbums, fetchedArtists, fetchedPlaylists, fetchedTracks, fetchedPodcasts, fetchedRadio) = try await (albumsTask, artistsTask, playlistsTask, tracksTask, podcastsTask, radioTask)

            let (sortedAlbums, sortedArtists, sortedPlaylists, sortedTracks, sortedPodcasts, sortedRadio) = await Task.detached(priority: .userInitiated) {
                let sortedAlbums = fetchedAlbums.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                let sortedArtists = fetchedArtists.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                let sortedPlaylists = fetchedPlaylists.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                let sortedTracks = fetchedTracks.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                let sortedPodcasts = fetchedPodcasts.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                let sortedRadio = fetchedRadio.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                
                return (sortedAlbums, sortedArtists, sortedPlaylists, sortedTracks, sortedPodcasts, sortedRadio)
            }.value

            self.albums = sortedAlbums
            self.artists = sortedArtists
            self.playlists = sortedPlaylists
            self.tracks = sortedTracks
            self.podcasts = sortedPodcasts
            self.radioStations = sortedRadio
            self.albumTotal = fetchedAlbums.total
            self.artistTotal = fetchedArtists.total
            self.playlistTotal = fetchedPlaylists.total
            self.songTotal = fetchedTracks.total
            self.podcastTotal = fetchedPodcasts.total
            self.radioTotal = fetchedRadio.total
            isLoading = false
            isNetworkFetching = false

            Task.detached(priority: .utility) {
                await self.cache.setAlbums(sortedAlbums)
                await self.cache.setArtists(sortedArtists)
                await self.cache.setPlaylists(sortedPlaylists)
                await self.cache.setTracks(sortedTracks)
                await self.cache.setPodcasts(sortedPodcasts)
                await self.cache.setRadioStations(sortedRadio)
            }

            print("[LibraryViewModel] Fetched and cached library (total: \(fetchedAlbums.total) albums, \(fetchedArtists.total) artists, \(fetchedPlaylists.total) playlists, \(fetchedTracks.total) tracks)")
        } catch {
            print("[LibraryViewModel] Network fetch failed: \(error)")
            if albums.isEmpty {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            isNetworkFetching = false
        }
    }

    func loadMoreAlbums() async {
        guard !isLoadingMoreAlbums, albums.count < albumTotal else { return }
        isLoadingMoreAlbums = true
        do {
            let result = try await client.fetchAlbums(offset: albums.count, limit: pageSize)
            let sorted = result.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            albums.append(contentsOf: sorted)
        } catch {
            print("[LibraryViewModel] Failed to load more albums: \(error)")
        }
        isLoadingMoreAlbums = false
    }

    func loadMoreSongs() async {
        guard !isLoadingMoreSongs, tracks.count < songTotal else { return }
        isLoadingMoreSongs = true
        do {
            let result = try await client.fetchTracks(offset: tracks.count, limit: pageSize)
            let sorted = result.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            tracks.append(contentsOf: sorted)
        } catch {
            print("[LibraryViewModel] Failed to load more songs: \(error)")
        }
        isLoadingMoreSongs = false
    }

    func loadMorePlaylists() async {
        guard !isLoadingMorePlaylists, playlists.count < playlistTotal else { return }
        isLoadingMorePlaylists = true
        do {
            let result = try await client.fetchPlaylists(offset: playlists.count, limit: pageSize)
            let sorted = result.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            playlists.append(contentsOf: sorted)
        } catch {
            print("[LibraryViewModel] Failed to load more playlists: \(error)")
        }
        isLoadingMorePlaylists = false
    }

    func loadMoreArtists() async {
        guard !isLoadingMoreArtists, artists.count < artistTotal else { return }
        isLoadingMoreArtists = true
        do {
            let result = try await client.fetchArtists(offset: artists.count, limit: pageSize)
            let sorted = result.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            artists.append(contentsOf: sorted)
        } catch {
            print("[LibraryViewModel] Failed to load more artists: \(error)")
        }
        isLoadingMoreArtists = false
    }

    func loadMorePodcasts() async {
        guard !isLoadingMorePodcasts, podcasts.count < podcastTotal else { return }
        isLoadingMorePodcasts = true
        do {
            let result = try await client.fetchPodcasts(offset: podcasts.count, limit: pageSize)
            let sorted = result.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            podcasts.append(contentsOf: sorted)
        } catch { print("[LibraryViewModel] Failed to load more podcasts: \(error)") }
        isLoadingMorePodcasts = false
    }

    func loadMoreRadio() async {
        guard !isLoadingMoreRadio, radioStations.count < radioTotal else { return }
        isLoadingMoreRadio = true
        do {
            let result = try await client.fetchRadioStations(offset: radioStations.count, limit: pageSize)
            let sorted = result.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            radioStations.append(contentsOf: sorted)
        } catch { print("[LibraryViewModel] Failed to load more radio: \(error)") }
        isLoadingMoreRadio = false
    }

    func loadPodcastEpisodes(podcast: Podcast) async throws -> [Episode] {
        if let cached = await cache.getPodcastEpisodes(podcastId: podcast.itemId) {
            return cached
        }
        let episodes = try await client.fetchPodcastEpisodes(podcastId: podcast.itemId, provider: podcast.provider)
        await cache.setPodcastEpisodes(episodes, podcastId: podcast.itemId)
        return episodes
    }

    func fetchLyrics(uri: String) async {
        do {
            lyrics = try await client.fetchLyrics(uri: uri)
        } catch { print("[LibraryViewModel] Failed to fetch lyrics: \(error)") }
    }

    func toggleFavorite<T: Identifiable>(item: T) async {
        var uri: String = ""
        var currentFavorite: Bool = false
        
        if let album = item as? Album {
            uri = album.uri
            currentFavorite = album.favorite ?? false
        } else if let artist = item as? Artist {
            uri = artist.uri
            currentFavorite = artist.favorite ?? false
        } else if let track = item as? Track {
            uri = track.uri
            currentFavorite = track.favorite ?? false
        } else if let playlist = item as? Playlist {
            uri = playlist.uri
            currentFavorite = playlist.favorite ?? false
        }
        
        guard !uri.isEmpty else { return }
        let newFavorite = !currentFavorite
        
        // Optimistically update local state
        updateLocalFavorite(uri: uri, favorite: newFavorite)
        
        do {
            try await client.toggleItemFavorite(uri: uri, favorite: newFavorite)
            // Update cache after successful server update
            if let album = item as? Album { await cache.setAlbums(albums) }
            else if let artist = item as? Artist { await cache.setArtists(artists) }
            else if let playlist = item as? Playlist { await cache.setPlaylists(playlists) }
        } catch {
            print("[LibraryViewModel] Failed to toggle favorite: \(error)")
            // Revert on error
            updateLocalFavorite(uri: uri, favorite: currentFavorite)
        }
    }

    private func updateLocalFavorite(uri: String, favorite: Bool) {
        if let index = albums.firstIndex(where: { $0.uri == uri }) {
            albums[index].favorite = favorite
        } else if let index = artists.firstIndex(where: { $0.uri == uri }) {
            artists[index].favorite = favorite
        } else if let index = playlists.firstIndex(where: { $0.uri == uri }) {
            playlists[index].favorite = favorite
        }
        
        // Also update search results if applicable
        if let index = searchResults.albums.firstIndex(where: { $0.uri == uri }) {
            searchResults.albums[index].favorite = favorite
        }
        if let index = searchResults.artists.firstIndex(where: { $0.uri == uri }) {
            searchResults.artists[index].favorite = favorite
        }
        if let index = searchResults.tracks.firstIndex(where: { $0.uri == uri }) {
            searchResults.tracks[index].favorite = favorite
        }
    }

    func loadAlbumTracks(album: Album) async throws -> [Track] {
        // Try cache first
        if let cached = await cache.getAlbumTracks(albumId: album.itemId) {
            return cached
        }

        let tracks = try await client.fetchAlbumTracks(albumId: album.itemId, provider: album.provider)

        // Cache the tracks
        await cache.setAlbumTracks(tracks, albumId: album.itemId)

        return tracks
    }

    func loadPlaylistTracks(playlist: Playlist) async throws -> [Track] {
        // Try cache first
        if let cached = await cache.getPlaylistTracks(playlistId: playlist.itemId) {
            return cached
        }

        let tracks = try await client.fetchPlaylistTracks(playlistId: playlist.itemId, provider: playlist.provider)

        // Cache the tracks
        await cache.setPlaylistTracks(tracks, playlistId: playlist.itemId)

        return tracks
    }

    func loadArtistDetails(artist: Artist) async throws -> (albums: [Album], tracks: [Track]) {
        // Try cache first
        let cachedAlbums = await cache.getArtistAlbums(artistId: artist.itemId)
        let cachedTracks = await cache.getArtistTracks(artistId: artist.itemId)

        if let albums = cachedAlbums, let tracks = cachedTracks {
            return (albums, tracks)
        }

        async let albumsTask = client.fetchArtistAlbums(artistId: artist.itemId, provider: artist.provider)
        async let tracksTask = client.fetchArtistTracks(artistId: artist.itemId, provider: artist.provider)

        let (fetchedAlbums, fetchedTracks) = try await (albumsTask, tracksTask)

        // Cache the results
        await cache.setArtistAlbums(fetchedAlbums, artistId: artist.itemId)
        await cache.setArtistTracks(fetchedTracks, artistId: artist.itemId)

        return (fetchedAlbums, fetchedTracks)
    }

    private func performSearch(_ query: String) async {
        searchTask?.cancel()

        searchTask = Task {
            isSearching = true

            do {
                let results = try await client.search(query: query)
                if !Task.isCancelled {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    print("Search error: \(error)")
                    isSearching = false
                }
            }
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = ([], [], [])
        isSearching = false
    }

    func refreshLibrary() async {
        await cache.invalidateLibrary()
        await loadLibrary(forceRefresh: true)
        NotificationCenter.default.post(name: .libraryUpdated, object: nil)
    }

    func clearCache() async {
        await cache.clearAll()
    }

    // MARK: - Sorted Data

    var sortedAlbums: [Album] {
        sortItems(albums, by: albumSort) as! [Album]
    }

    var sortedTracks: [Track] {
        sortItems(tracks, by: songSort) as! [Track]
    }

    var sortedPlaylists: [Playlist] {
        sortItems(playlists, by: playlistSort) as! [Playlist]
    }

    var sortedArtists: [Artist] {
        sortItems(artists, by: artistSort) as! [Artist]
    }

    private func sortItems<T: Identifiable>(_ items: [T], by option: LibrarySortOption) -> [T] {
        switch option {
        case .name:
            return sortByName(items)
        case .artist:
            return sortByArtist(items)
        case .year:
            if let albums = items as? [Album] {
                return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) } as! [T]
            }
            return items
        case .recentlyAdded:
            return items
        }
    }

    private func sortByName<T: Identifiable>(_ items: [T]) -> [T] {
        items.sorted { left, right in
            let nameL = (left as? Album)?.name ?? (left as? Artist)?.name ?? (left as? Playlist)?.name ?? (left as? Track)?.name ?? ""
            let nameR = (right as? Album)?.name ?? (right as? Artist)?.name ?? (right as? Playlist)?.name ?? (right as? Track)?.name ?? ""
            return nameL.localizedCaseInsensitiveCompare(nameR) == .orderedAscending
        }
    }

    private func sortByArtist<T: Identifiable>(_ items: [T]) -> [T] {
        items.sorted { left, right in
            let artistL = (left as? Track)?.artistNames ?? (left as? Album)?.artistNames ?? ""
            let artistR = (right as? Track)?.artistNames ?? (right as? Album)?.artistNames ?? ""
            if artistL != artistR { return artistL.localizedCaseInsensitiveCompare(artistR) == .orderedAscending }
            let nameL = (left as? Track)?.name ?? (left as? Album)?.name ?? ""
            let nameR = (right as? Track)?.name ?? (right as? Album)?.name ?? ""
            return nameL.localizedCaseInsensitiveCompare(nameR) == .orderedAscending
        }
    }

    func setAlbumSort(_ option: LibrarySortOption) {
        albumSort = option
        saveSortPreferences()
    }

    func setAlbumViewMode(_ mode: LibraryViewMode) {
        albumViewMode = mode
        saveSortPreferences()
    }

    func setSongSort(_ option: LibrarySortOption) {
        songSort = option
        saveSortPreferences()
    }

    func setPlaylistSort(_ option: LibrarySortOption) {
        playlistSort = option
        saveSortPreferences()
    }

    func setPlaylistViewMode(_ mode: LibraryViewMode) {
        playlistViewMode = mode
        saveSortPreferences()
    }

    func setArtistSort(_ option: LibrarySortOption) {
        artistSort = option
        saveSortPreferences()
    }
}
