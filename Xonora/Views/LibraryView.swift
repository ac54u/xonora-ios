import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var selectedCategory: LibraryCategory = .playlists
    @State private var isInitialLoad = true

    enum LibraryCategory: String, CaseIterable, Identifiable {
        case playlists = "Playlists"
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
        case podcasts = "Podcasts"
        case radio = "Radio"

        var id: String { self.rawValue }

        var localizedName: String {
            NSLocalizedString(self.rawValue, comment: "Library category")
        }

        var icon: String {
            switch self {
            case .playlists: return "music.note.list"
            case .songs: return "music.quarternote.3"
            case .albums: return "rectangle.stack.fill"
            case .artists: return "person.2.circle.fill"
            case .podcasts: return "mic.fill"
            case .radio: return "radio"
            }
        }
    }

    @State private var columnCount: Int = UserDefaults.standard.integer(forKey: "gridColumnCount") != 0
        ? UserDefaults.standard.integer(forKey: "gridColumnCount")
        : 2
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? min(columnCount + 2, 6) : columnCount
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: max(count, 2))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if (libraryViewModel.isLoading || isInitialLoad) && libraryViewModel.albums.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Loading Library...")
                            .controlSize(.large)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = libraryViewModel.errorMessage, libraryViewModel.albums.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await libraryViewModel.loadLibrary()
                            }
                        }
                    }
                } else {
                    TabView(selection: $selectedCategory) {
                        categoryScrollView { playlistsContent }.tag(LibraryCategory.playlists)
                        categoryScrollView { songsList }.tag(LibraryCategory.songs)
                        categoryScrollView { albumsContent }.tag(LibraryCategory.albums)
                        categoryScrollView { artistsList }.tag(LibraryCategory.artists)
                        categoryScrollView { podcastsContent }.tag(LibraryCategory.podcasts)
                        categoryScrollView { radioContent }.tag(LibraryCategory.radio)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .safeAreaInset(edge: .top, spacing: 0) {
                        categoryTabBar
                    }
                }
            }
            .navigationBarHidden(true)
            .background(Color(UIColor.systemGroupedBackground))
        }
        .task {
            await libraryViewModel.loadLibrary()
            isInitialLoad = false
        }
        .onChange(of: playerViewModel.isConnected) { oldValue, connected in
            if connected {
                Task {
                    await libraryViewModel.loadLibrary()
                }
            }
        }
    }

    private var categoryTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(LibraryCategory.allCases) { category in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedCategory = category
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.system(size: 20))
                                .symbolVariant(selectedCategory == category ? .fill : .none)

                            Text(category.localizedName)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .foregroundColor(selectedCategory == category ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            Divider().background(Color.primary.opacity(0.1))

            sortViewBar
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var sortViewBar: some View {
        HStack {
            sortPicker
            Spacer()
            viewModeToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var sortPicker: some View {
        let sortBinding = Binding<LibrarySortOption>(
            get: {
                switch selectedCategory {
                case .albums: return libraryViewModel.albumSort
                case .songs: return libraryViewModel.songSort
                case .playlists: return libraryViewModel.playlistSort
                case .artists: return libraryViewModel.artistSort
                case .podcasts, .radio: return .name
                }
            },
            set: { newValue in
                switch selectedCategory {
                case .albums: libraryViewModel.setAlbumSort(newValue)
                case .songs: libraryViewModel.setSongSort(newValue)
                case .playlists: libraryViewModel.setPlaylistSort(newValue)
                case .artists: libraryViewModel.setArtistSort(newValue)
                case .podcasts, .radio: break
                }
            }
        )

        let availableSortOptions: [LibrarySortOption] = {
            switch selectedCategory {
            case .albums: return [.name, .artist, .year, .recentlyAdded]
            case .songs: return [.name, .artist, .recentlyAdded]
            case .playlists: return [.name, .recentlyAdded]
            case .artists: return [.name]
            case .podcasts, .radio: return [.name]
            }
        }()

        Picker("Sort", selection: sortBinding) {
            ForEach(availableSortOptions, id: \.self) { option in
                Text(option.localizedName).tag(option)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
    }

    @ViewBuilder
    private var viewModeToggle: some View {
        switch selectedCategory {
        case .albums:
            HStack(spacing: 8) {
                viewModeButton(
                    isGrid: libraryViewModel.albumViewMode == .grid,
                    toggle: { libraryViewModel.setAlbumViewMode(libraryViewModel.albumViewMode == .grid ? .list : .grid) }
                )
                if libraryViewModel.albumViewMode == .grid {
                    Menu {
                        ForEach(2...4, id: \.self) { count in
                            Button(String.localizedStringWithFormat(NSLocalizedString("%lld Columns", comment: ""), count)) {
                                columnCount = count
                                UserDefaults.standard.set(count, forKey: "gridColumnCount")
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.split.2x2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .playlists:
            HStack(spacing: 8) {
                viewModeButton(
                    isGrid: libraryViewModel.playlistViewMode == .grid,
                    toggle: { libraryViewModel.setPlaylistViewMode(libraryViewModel.playlistViewMode == .grid ? .list : .grid) }
                )
                if libraryViewModel.playlistViewMode == .grid {
                    Menu {
                        ForEach(2...4, id: \.self) { count in
                            Button(String.localizedStringWithFormat(NSLocalizedString("%lld Columns", comment: ""), count)) {
                                columnCount = count
                                UserDefaults.standard.set(count, forKey: "gridColumnCount")
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.split.2x2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func viewModeButton(isGrid: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                .font(.caption)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func categoryScrollView<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.top, 16)
        }
        .refreshable {
            await libraryViewModel.refresh()
        }
    }

    // MARK: - Albums

    @ViewBuilder
    private var albumsContent: some View {
        if libraryViewModel.sortedAlbums.isEmpty && !libraryViewModel.isLoading {
            emptyView("No Albums", icon: "rectangle.stack.fill", message: "Your library is empty. Add some music to get started.")
        } else if libraryViewModel.albumViewMode == .grid {
            albumsGrid
        } else {
            albumsList
        }
    }

    private var albumsGrid: some View {
        LazyVStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(libraryViewModel.sortedAlbums) { album in
                    NavigationLink(destination: AlbumDetailView(album: album)) {
                        AlbumGridItem(album: album)
                    }
                    .buttonStyle(.plain)
                }

                if libraryViewModel.albums.count < libraryViewModel.albumTotal {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task {
                            await libraryViewModel.loadMoreAlbums()
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
        }
    }

    private var albumsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(libraryViewModel.sortedAlbums.enumerated()), id: \.element.id) { index, album in
                NavigationLink(destination: AlbumDetailView(album: album)) {
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl, size: .thumbnail)) {
                            Color.clear
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.name)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(album.artistNames)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let year = album.year {
                            Text(String(year))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < libraryViewModel.sortedAlbums.count - 1 {
                    Divider().padding(.leading, 68)
                }
            }

            if libraryViewModel.albums.count < libraryViewModel.albumTotal {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .task {
                        await libraryViewModel.loadMoreAlbums()
                    }
            }
        }
        .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
    }

    // MARK: - Songs

    private var songsList: some View {
        let sorted = libraryViewModel.sortedTracks

        return LazyVStack(spacing: 0) {
            if sorted.isEmpty && !libraryViewModel.isLoading {
                emptyView("No Songs", icon: "music.quarternote.3", message: "Your library has no songs.")
            } else {
                ForEach(sorted) { track in
                    TrackRow(
                        track: track,
                        showArtwork: true,
                        isPlaying: playerViewModel.currentTrack?.itemId == track.itemId
                    ) {
                        playerViewModel.playTrack(track, fromQueue: libraryViewModel.sortedTracks, sourceName: "Songs")
                    }
                    .padding(.horizontal, 12)
                }
                if libraryViewModel.tracks.count < libraryViewModel.songTotal {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task { await libraryViewModel.loadMoreSongs() }
                }
            }
        }
        .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
    }

    // MARK: - Playlists

    @ViewBuilder
    private var playlistsContent: some View {
        if libraryViewModel.sortedPlaylists.isEmpty && !libraryViewModel.isLoading {
            emptyView("No Playlists", icon: "music.note.list", message: "Your library has no playlists.")
        } else if libraryViewModel.playlistViewMode == .grid {
            playlistsGrid
        } else {
            playlistsList
        }
    }

    private var playlistsGrid: some View {
        LazyVStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(libraryViewModel.sortedPlaylists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                        PlaylistGridItem(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }

                if libraryViewModel.playlists.count < libraryViewModel.playlistTotal {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task {
                            await libraryViewModel.loadMorePlaylists()
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
        }
    }

    private var playlistsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(libraryViewModel.sortedPlaylists.enumerated()), id: \.element.id) { index, playlist in
                NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: playlist.imageUrl, size: .thumbnail)) {
                            Color.clear
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.displayName)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text("Playlist")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < libraryViewModel.sortedPlaylists.count - 1 {
                    Divider().padding(.leading, 68)
                }
            }

            if libraryViewModel.playlists.count < libraryViewModel.playlistTotal {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .task {
                        await libraryViewModel.loadMorePlaylists()
                    }
            }
        }
        .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
    }

    // MARK: - Artists

    private var artistsList: some View {
        let sorted = libraryViewModel.sortedArtists

        return LazyVStack(spacing: 0) {
            if sorted.isEmpty && !libraryViewModel.isLoading {
                emptyView("No Artists", icon: "person.2.circle.fill", message: "Your library is empty.")
            } else {
                ForEach(sorted) { artist in
                            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                                HStack(spacing: 12) {
                                    CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: artist.imageUrl, size: .thumbnail)) {
                                        Color.clear
                                    }
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(artist.name).font(.body).foregroundColor(.primary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundColor(.secondary.opacity(0.5))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                if libraryViewModel.artists.count < libraryViewModel.artistTotal {
                    ProgressView()
                        .frame(maxWidth: .infinity).padding()
                        .task { await libraryViewModel.loadMoreArtists() }
                }
            }
        }
        .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
    }

    // MARK: - Podcasts

    @ViewBuilder
    private var podcastsContent: some View {
        if libraryViewModel.podcasts.isEmpty && !libraryViewModel.isLoading {
            emptyView("No Podcasts", icon: "mic.fill", message: "Your library has no podcasts.")
        } else {
            LazyVStack(spacing: 0) {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(libraryViewModel.podcasts) { podcast in
                        NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                            PodcastGridItem(podcast: podcast)
                        }
                        .buttonStyle(.plain)
                    }
                    if libraryViewModel.podcasts.count < libraryViewModel.podcastTotal {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .task { await libraryViewModel.loadMorePodcasts() }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
            }
        }
    }

    // MARK: - Radio

    @ViewBuilder
    private var radioContent: some View {
        if libraryViewModel.radioStations.isEmpty && !libraryViewModel.isLoading {
            emptyView("No Radio Stations", icon: "radio", message: "Your library has no radio stations.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(libraryViewModel.radioStations) { station in
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: station.imageUrl, size: .thumbnail)) {
                            Color.clear
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.name)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            if let desc = station.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        Button {
                            playRadioStation(station)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())

                    Divider().padding(.leading, 68)
                }
                if libraryViewModel.radioStations.count < libraryViewModel.radioTotal {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task { await libraryViewModel.loadMoreRadio() }
                }
            }
            .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
        }
    }

    private func playRadioStation(_ station: RadioStation) {
        let track = Track(
            itemId: station.itemId,
            provider: station.provider,
            name: station.name,
            version: nil,
            duration: nil,
            trackNumber: nil,
            discNumber: nil,
            uri: station.uri,
            artists: nil,
            album: nil,
            metadata: station.metadata,
            providerMappings: nil,
            favorite: station.favorite
        )
        playerViewModel.playTrack(track, sourceName: "Radio")
    }

    private func emptyView(_ title: LocalizedStringKey, icon: String, message: LocalizedStringKey) -> some View {
        ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text(message)
        )
        .padding(.top, 100)
    }
}

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(LibraryViewModel())
            .environmentObject(PlayerViewModel())
    }
}
