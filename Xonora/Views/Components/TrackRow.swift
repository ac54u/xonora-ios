import SwiftUI

struct TrackRow: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    let track: Track
    let showArtwork: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    init(track: Track, showArtwork: Bool = false, isPlaying: Bool = false, onTap: @escaping () -> Void) {
        self.track = track
        self.showArtwork = showArtwork
        self.isPlaying = isPlaying
        self.onTap = onTap
    }

    var body: some View {
        // The row is a plain HStack — NOT one big Button — so that the heart and the
        // "…" menu are independently tappable. Nesting them inside an outer Button made
        // every tap (including on those controls) fall through to onTap (play).
        HStack(spacing: 12) {
            // Tappable content area: number / artwork / info / duration → onTap (play).
            Button(action: onTap) {
                HStack(spacing: 12) {
                    if isPlaying {
                        playingIndicator
                    }

                    if showArtwork {
                        CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: track.imageUrl ?? track.album?.imageUrl, size: .thumbnail)) {
                            Color.clear
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.body)
                            .foregroundColor(isPlaying ? .accentColor : .primary)
                            .lineLimit(1)

                        Text(track.artistNames)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(track.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Favorite toggle — independent control.
            Button {
                Task {
                    await libraryViewModel.toggleFavorite(item: track)
                }
            } label: {
                Image(systemName: (track.favorite ?? false) ? "heart.fill" : "heart")
                    .foregroundColor((track.favorite ?? false) ? .pink : .secondary)
                    .font(.body)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // More options menu — independent control.
            Menu {
                Button {
                    PlayerManager.shared.playTrack(track)
                } label: {
                    Label("Play", systemImage: "play")
                }

                if let album = track.album {
                    Button {
                        Task {
                            if let tracks = try? await XonoraClient.shared.fetchAlbumTracks(albumId: album.itemId, provider: album.provider) {
                                await MainActor.run {
                                    PlayerManager.shared.playAlbum(tracks)
                                }
                            }
                        }
                    } label: {
                        Label("Play Album", systemImage: "opticaldisc")
                    }
                }

                Button {
                    PlayerManager.shared.playNext(track)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    PlayerManager.shared.addToQueue(track)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }

                if track.provider != "library" {
                    Button {
                        Task {
                            try? await XonoraClient.shared.addToLibrary(itemId: track.itemId, provider: track.provider)
                        }
                    } label: {
                        Label("Add to Library", systemImage: "plus.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var playingIndicator: some View {
        Group {
            if #available(iOS 17.0, *) {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor.iterative)
            } else {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: 24)
    }
}

struct TrackRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TrackRow(
                track: Track(
                    itemId: "1",
                    provider: "apple_music",
                    name: "Sample Track",
                    version: nil,
                    duration: 210,
                    trackNumber: 1,
                    discNumber: 1,
                    uri: "apple_music://track/1",
                    artists: [ArtistReference(itemId: "1", provider: "apple_music", name: "Sample Artist")],
                    album: nil,
                    metadata: nil,
                    providerMappings: nil
                ),
                showArtwork: true,
                isPlaying: false,
                onTap: {}
            )

            TrackRow(
                track: Track(
                    itemId: "2",
                    provider: "apple_music",
                    name: "Currently Playing Track",
                    version: nil,
                    duration: 185,
                    trackNumber: 2,
                    discNumber: 1,
                    uri: "apple_music://track/2",
                    artists: [ArtistReference(itemId: "1", provider: "apple_music", name: "Sample Artist")],
                    album: nil,
                    metadata: nil,
                    providerMappings: nil
                ),
                showArtwork: true,
                isPlaying: true,
                onTap: {}
            )
        }
        .padding()
    }
}
