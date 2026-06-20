import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    private let playerManager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentLineId: String?

    var body: some View {
        NavigationStack {
            Group {
                if let lyrics = libraryViewModel.lyrics?.lyrics, !lyrics.isEmpty {
                    if libraryViewModel.lyrics?.hasSynced == true {
                        syncedLyricsView(lyrics)
                    } else {
                        staticLyricsView(lyrics)
                    }
                } else {
                    ContentUnavailableView(
                        "No Lyrics",
                        systemImage: "text.alignleft",
                        description: Text("Lyrics not available for this track")
                    )
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if let track = playerManager.currentTrack {
                await libraryViewModel.fetchLyrics(track: track)
            }
        }
        .onChange(of: playerManager.currentTrack?.uri) { _, _ in
            guard let track = playerManager.currentTrack else { return }
            Task {
                await libraryViewModel.fetchLyrics(track: track)
            }
        }
    }

    private func syncedLyricsView(_ lyrics: [Lyric]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(lyrics) { line in
                        Text(line.text)
                            .font(.title3)
                            .foregroundColor(line.id == currentLineId ? .primary : .secondary)
                            .fontWeight(line.id == currentLineId ? .bold : .regular)
                            .id(line.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .onReceive(playerManager.$currentTime) { time in
                let matched = lyrics.first(where: { $0.start ?? 0 <= time && ($0.end ?? Double.greatestFiniteMagnitude) >= time })
                if matched?.id != currentLineId {
                    currentLineId = matched?.id
                    if let id = matched?.id {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func staticLyricsView(_ lyrics: [Lyric]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lyrics) { line in
                    Text(line.text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }
}
