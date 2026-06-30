import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast

    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var episodes: [Episode] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                podcastHeader
                    .padding(.bottom, 24)

                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await loadEpisodes()
                            }
                        }
                    }
                    .padding(.top, 40)
                } else if episodes.isEmpty {
                    ContentUnavailableView {
                        Label("No Episodes", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("This podcast has no episodes.")
                    }
                    .padding(.top, 40)
                } else {
                    episodeList
                }
            }
            .padding(.bottom, playerViewModel.hasTrack ? 120 : 50)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await libraryViewModel.toggleFavorite(item: podcast)
                    }
                } label: {
                    Image(systemName: (libraryViewModel.podcasts.first(where: { $0.id == podcast.id })?.favorite ?? podcast.favorite ?? false) ? "heart.fill" : "heart")
                        .foregroundColor((libraryViewModel.podcasts.first(where: { $0.id == podcast.id })?.favorite ?? podcast.favorite ?? false) ? .pink : .primary)
                }
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .task {
            await loadEpisodes()
        }
    }

    private var podcastHeader: some View {
        VStack(spacing: 16) {
            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: podcast.imageUrl, size: .medium)) {
                Color.clear
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)

            VStack(spacing: 4) {
                Text(podcast.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                if let total = podcast.totalEpisodes {
                    Text(String.localizedStringWithFormat(NSLocalizedString("%lld episodes", comment: "Episode count"), total))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top)
    }

    private var episodeList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                Button {
                    playEpisode(episode)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                Text(episode.formattedDuration)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let description = episode.description {
                                    Text(verbatim: "\u{00B7}")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "play.circle")
                            .font(.title3)
                            .foregroundColor(.pink)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < episodes.count - 1 {
                    Divider()
                        .padding(.leading)
                }
            }
        }
    }

    private func playEpisode(_ episode: Episode) {
        let track = Track(
            itemId: episode.itemId,
            provider: episode.provider,
            name: episode.name,
            version: nil,
            duration: episode.duration,
            trackNumber: nil,
            discNumber: nil,
            uri: episode.uri,
            artists: nil,
            album: nil,
            metadata: episode.metadata,
            providerMappings: nil,
            favorite: nil
        )
        playerViewModel.playTrack(track, sourceName: episode.podcastName ?? podcast.name)
    }

    private func loadEpisodes() async {
        isLoading = true
        errorMessage = nil

        do {
            episodes = try await libraryViewModel.loadPodcastEpisodes(podcast: podcast)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct PodcastDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PodcastDetailView(podcast: Podcast(
                itemId: "1",
                provider: "apple_music",
                name: "Sample Podcast",
                uri: "apple_music://podcast/1",
                metadata: nil,
                totalEpisodes: 42
            ))
        }
        .environmentObject(LibraryViewModel())
        .environmentObject(PlayerViewModel())
    }
}
