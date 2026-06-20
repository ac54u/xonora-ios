import SwiftUI

struct RadioStationListView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    @State private var isLoading = false

    var body: some View {
        ScrollView {
            if isLoading && libraryViewModel.radioStations.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading Radio Stations...")
                        .controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else if libraryViewModel.radioStations.isEmpty {
                ContentUnavailableView {
                    Label("No Radio Stations", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Your library has no radio stations.")
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(libraryViewModel.radioStations.enumerated()), id: \.element.id) { index, station in
                        Button {
                            playStation(station)
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: station.imageUrl, size: .thumbnail)) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "dot.radiowaves.left.and.right")
                                                .foregroundColor(.gray)
                                        }
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    if let description = station.description {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()

                                Image(systemName: "play.circle")
                                    .font(.title3)
                                    .foregroundColor(.pink)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < libraryViewModel.radioStations.count - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }

                    if libraryViewModel.radioStations.count < libraryViewModel.radioTotal {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .task {
                                await libraryViewModel.loadMoreRadio()
                            }
                    }
                }
                .padding(.bottom, playerViewModel.hasTrack ? 120 : 20)
            }
        }
        .refreshable {
            await loadRadioStations()
        }
        .navigationTitle("Radio Stations")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground))
        .task {
            if libraryViewModel.radioStations.isEmpty {
                await loadRadioStations()
            }
        }
    }

    private func loadRadioStations() async {
        guard !isLoading else { return }
        isLoading = true
        libraryViewModel.errorMessage = nil
        do {
            let result = try await XonoraClient.shared.fetchRadioStations()
            libraryViewModel.radioStations = result.items
            libraryViewModel.radioTotal = result.total
        } catch {
            libraryViewModel.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func playStation(_ station: RadioStation) {
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
}

struct RadioStationListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RadioStationListView()
        }
        .environmentObject(LibraryViewModel())
        .environmentObject(PlayerViewModel())
    }
}
