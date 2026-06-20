import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var selectedCategory: LibraryCategory = .albums
    @State private var isInitialLoad = true

    enum LibraryCategory: String, CaseIterable, Identifiable {
        case albums = "Albums"
        case songs = "Songs"
        case playlists = "Playlists"
        case artists = "Artists"

        var id: String { self.rawValue }

        var localizedName: String {
            NSLocalizedString(self.rawValue, comment: "Library category")
        }

        var icon: String {
            switch self {
            case .albums: return "square.stack.fill"
            case .songs: return "music.note"
            case .playlists: return "music.note.list"
            case .artists: return "person.2.fill"
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

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
                        categoryScrollView { albumsContent }.tag(LibraryCategory.albums)
                        categoryScrollView { songsList }.tag(LibraryCategory.songs)
                        categoryScrollView { playlistsContent }.tag(LibraryCategory.playlists)
                        categoryScrollView { artistsList }.tag(LibraryCategory.artists)
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
                }
            },
            set: { newValue in
                switch selectedCategory {
                case .albums: libraryViewModel.setAlbumSort(newValue)
                case .songs: libraryViewModel.setSongSort(newValue)
                case .playlists: libraryViewModel.setPlaylistSort(newValue)
                case .artists: libraryViewModel.setArtistSort(newValue)
                }
            }
        )

        let availableSortOptions: [LibrarySortOption] = {
            switch selectedCategory {
            case .albums: return [.name, .artist, .year, .recentlyAdded]
            case .songs: return [.name, .artist, .recentlyAdded]
            case .playlists: return [.name, .recentlyAdded]
            case .artists: return [.name]
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
            viewModeButton(
                isGrid: libraryViewModel.albumViewMode == .grid,
                toggle: { libraryViewModel.setAlbumViewMode(libraryViewModel.albumViewMode == .grid ? .list : .grid) }
            )
        case .playlists:
            viewModeButton(
                isGrid: libraryViewModel.playlistViewMode == .grid,
                toggle: { libraryViewModel.setPlaylistViewMode(libraryViewModel.playlistViewMode == .grid ? .list : .grid) }
            )
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
            await libraryViewModel.loadLibrary(forceRefresh: true)
        }
    }

    // MARK: - Albums

    @ViewBuilder
    private var albumsContent: some View {
        if libraryViewModel.sortedAlbums.isEmpty && !libraryViewModel.isLoading {
            emptyView("No Albums", icon: "square.stack", message: "Your library is empty. Add some music to get started.")
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
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.3))
                                .overlay {
                                    Image(systemName: "music.note")
                                        .foregroundColor(.gray)
                                }
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
        LazyVStack(spacing: 0) {
            if libraryViewModel.sortedTracks.isEmpty && !libraryViewModel.isLoading {
                emptyView("No Songs", icon: "music.note", message: "Your library has no songs. Add individual tracks to see them here.")
            } else {
                ForEach(Array(libraryViewModel.sortedTracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track: track,
                        index: index + 1,
                        showArtwork: true,
                        isPlaying: playerViewModel.currentTrack?.itemId == track.itemId,
                        numberFirst: true
                    ) {
                        playerViewModel.playTrack(track, sourceName: "Songs")
                    }
                    .padding(.horizontal, 12)
                }

                if libraryViewModel.tracks.count < libraryViewModel.songTotal {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task {
                            await libraryViewModel.loadMoreSongs()
                        }
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
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.3))
                                .overlay {
                                    Image(systemName: "music.note.list")
                                        .foregroundColor(.gray)
                                }
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name)
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
        LazyVStack(spacing: 0) {
            if libraryViewModel.sortedArtists.isEmpty && !libraryViewModel.isLoading {
                emptyView("No Artists", icon: "person.2", message: "Your library is empty.")
            } else {
                ForEach(libraryViewModel.sortedArtists) { artist in
                    NavigationLink(destination: ArtistDetailView(artist: artist)) {
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: artist.imageUrl, size: .thumbnail)) {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                    }
                            }
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
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
                }

                if libraryViewModel.artists.count < libraryViewModel.artistTotal {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task {
                            await libraryViewModel.loadMoreArtists()
                        }
                }
            }
        }
        .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
    }

    private func emptyView(_ title: String, icon: String, message: String) -> some View {
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
