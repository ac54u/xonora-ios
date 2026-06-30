import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var albums: [Album] = []
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFavorite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerView

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else {
                    // Top Tracks
                    if !tracks.isEmpty {
                        tracksSection
                    }

                    // Albums
                    if !albums.isEmpty {
                        albumsSection
                    }
                }
            }
            .padding(.bottom, playerViewModel.hasTrack ? 120 : 50)
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let previousValue = isFavorite
                    let newValue = !previousValue
                    isFavorite = newValue
                    Task {
                        await libraryViewModel.toggleFavorite(item: artist)
                        // Revert optimistic update on failure
                        await MainActor.run {
                            if self.isFavorite == newValue,
                               libraryViewModel.artists.first(where: { $0.id == artist.id })?.favorite != newValue {
                                self.isFavorite = previousValue
                            }
                        }
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : .primary)
                }
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .task(id: artist.id) { isFavorite = artist.favorite ?? false }
        .task {
            await loadData()
        }
    }

    private var headerView: some View {
        HStack(spacing: 20) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: artist.imageUrl, size: .medium)) {
                Color.clear
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .shadow(radius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .lineLimit(2)
                
                Text("Artist")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }

    private var tracksSection: some View {
        VStack(alignment: .leading) {
            Text("Top Songs")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ForEach(tracks.prefix(5)) { track in
                TrackRow(
                    track: track,
                    showArtwork: true,
                    isPlaying: playerViewModel.currentTrack?.id == track.id
                ) {
                    Task {
                        // Play artist tracks starting from this one
                        playerViewModel.playTrack(track, fromQueue: tracks, sourceName: artist.name)
                    }
                }
                .padding(.horizontal)
            }
            
            if tracks.count > 5 {
                NavigationLink("See all songs") {
                    List {
                        ForEach(tracks) { track in
                            TrackRow(
                                track: track,
                                showArtwork: true,
                                isPlaying: playerViewModel.currentTrack?.id == track.id
                            ) {
                                Task {
                                    playerViewModel.playTrack(track, fromQueue: tracks, sourceName: artist.name)
                                }
                            }
                        }
                    }
                    .navigationTitle("Songs")
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading) {
            Text("Albums")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            VStack(alignment: .leading) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl)) {
                                    Color.clear
                                }
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(album.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                
                                Text(String(album.year ?? 0))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 140)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadData() async {
        do {
            let (fetchedAlbums, fetchedTracks) = try await libraryViewModel.loadArtistDetails(artist: artist)
            // Sort albums by year descending
            self.albums = fetchedAlbums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            self.tracks = fetchedTracks
            isLoading = false
        } catch {
            errorMessage = NSLocalizedString("Failed to load artist details", comment: "")
            isLoading = false
        }
    }
}
