import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss

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
            if let uri = playerManager.currentTrack?.uri {
                await libraryViewModel.fetchLyrics(uri: uri)
            }
        }
        .onChange(of: playerManager.currentTrack?.uri) { _, newURI in
            guard let uri = newURI else { return }
            Task {
                await libraryViewModel.fetchLyrics(uri: uri)
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
                            .foregroundColor(isCurrentLine(line) ? .primary : .secondary)
                            .fontWeight(isCurrentLine(line) ? .bold : .regular)
                            .id(line.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .onReceive(playerManager.$currentTime) { time in
                if let currentLine = lyrics.first(where: { $0.start ?? 0 <= time && ($0.end ?? Double.greatestFiniteMagnitude) >= time }) {
                    withAnimation {
                        proxy.scrollTo(currentLine.id, anchor: .center)
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

    private func isCurrentLine(_ line: Lyric) -> Bool {
        guard let start = line.start, let end = line.end else { return false }
        return playerManager.currentTime >= start && playerManager.currentTime <= end
    }
}
