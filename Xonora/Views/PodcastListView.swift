import SwiftUI

struct PodcastListView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var isLoading = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if isLoading && libraryViewModel.podcasts.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading Podcasts...")
                        .controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else if libraryViewModel.podcasts.isEmpty {
                ContentUnavailableView {
                    Label("No Podcasts", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Your library has no podcasts.")
                }
            } else {
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
                            .task {
                                await libraryViewModel.loadMorePodcasts()
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
            }
        }
        .refreshable {
            await loadPodcasts()
        }
        .navigationTitle("Podcasts")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground))
        .task {
            if libraryViewModel.podcasts.isEmpty {
                await loadPodcasts()
            }
        }
    }

    private func loadPodcasts() async {
        guard !isLoading else { return }
        isLoading = true
        libraryViewModel.errorMessage = nil
        do {
            let result = try await XonoraClient.shared.fetchPodcasts()
            libraryViewModel.podcasts = result.items
            libraryViewModel.podcastTotal = result.total
        } catch {
            libraryViewModel.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
