import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var isPresentedModally: Bool = true

    @State private var dragOffset: CGFloat = 0
    @State private var showQueue = false
    @State private var showPlayerPicker = false
    @State private var showLyrics = false
    @State private var showSleepTimer = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.top, 16) // Standard padding

            Spacer()

            // Album artwork
            albumArtwork
                .padding(.horizontal, 40)
                .padding(.vertical, 20)

            Spacer()

            // Track info
            trackInfo
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            // Controls
            PlayerControls(playerManager: playerManager, size: .full)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .colorScheme(.dark)
        .background(
            albumArtView.ignoresSafeArea()
        )
        .gesture(
            isPresentedModally ? 
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    }
                    dragOffset = 0
                }
            : nil
        )
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .sheet(isPresented: $showPlayerPicker) {
            PlayerPickerView()
        }
        .sheet(isPresented: $showLyrics) {
            LyricsView()
        }
        .actionSheet(isPresented: $showSleepTimer) {
            ActionSheet(
                title: Text("Sleep Timer"),
                buttons: [
                    .default(Text("15 minutes")) { playerManager.setSleepTimer(minutes: 15) },
                    .default(Text("30 minutes")) { playerManager.setSleepTimer(minutes: 30) },
                    .default(Text("45 minutes")) { playerManager.setSleepTimer(minutes: 45) },
                    .default(Text("60 minutes")) { playerManager.setSleepTimer(minutes: 60) },
                    .default(Text("End of Track")) { playerManager.setSleepTimerEndOfTrack() },
                    .cancel(Text("Cancel"))
                ]
            )
        }
    }
    
    private var albumArtView: some View {
        ZStack {
            AsyncImage(url: trackImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 30) // Reduced from 60 to improve rendering performance
                        .scaleEffect(1.1)
                case .failure, .empty:
                    Color.xonoraGradient
                @unknown default:
                    Color.xonoraGradient
                }
            }

            Color.black.opacity(0.5)
        }
    }

    private var header: some View {
        HStack {
            if isPresentedModally {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
            } else {
                Spacer().frame(width: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                if playerManager.sleepTimerActive {
                    Text(playerManager.sleepTimerDescription)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                } else {
                    Text("PLAYING FROM")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                }

                Text(playerManager.currentSource ?? playerManager.currentTrack?.album?.name ?? NSLocalizedString("Library", comment: ""))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    showSleepTimer = true
                } label: {
                    Image(systemName: playerManager.sleepTimerActive ? "timer" : "timer")
                        .font(.title2)
                        .foregroundColor(playerManager.sleepTimerActive ? .orange : .white)
                        .frame(width: 44, height: 44)
                }

                Button {
                    showLyrics = true
                } label: {
                    Image(systemName: "text.alignleft")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }

                Button {
                    showQueue = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal)
    }

    private var albumArtwork: some View {
        AsyncImage(url: trackImageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                artworkPlaceholder
            case .empty:
                artworkPlaceholder
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            @unknown default:
                artworkPlaceholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
        .scaleEffect(playerManager.isPlaying ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 0.3), value: playerManager.isPlaying)
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [.gray.opacity(0.4), .gray.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.5))
            }
    }

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text(playerManager.currentTrack?.name ?? NSLocalizedString("Not Playing", comment: ""))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)

            Text(playerManager.currentTrack?.artistNames ?? "")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private var trackImageURL: URL? {
        let imageString = playerManager.currentTrack?.imageUrl ?? playerManager.currentTrack?.album?.imageUrl
        return XonoraClient.shared.getImageURL(for: imageString, size: .large)
    }

    private var thumbnailImageURL: URL? {
        let imageString = playerManager.currentTrack?.imageUrl ?? playerManager.currentTrack?.album?.imageUrl
        return XonoraClient.shared.getImageURL(for: imageString, size: .thumbnail)
    }
}

struct QueueView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if playerManager.queue.isEmpty {
                    emptyQueueView
                } else {
                    queueSection
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !playerManager.queue.isEmpty {
                        Button("Clear") {
                            playerManager.clearQueue()
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyQueueView: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "Queue is Empty",
                systemImage: "music.note.list",
                description: Text("Add some songs to your queue")
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                Text("Queue is Empty")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Add some songs to your queue")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
    
    private var queueSection: some View {
        Section {
            ForEach(Array(playerManager.queue.enumerated()), id: \.element.id) { index, track in
                queueRow(for: track, at: index)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerManager.playTrack(track)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation {
                                playerManager.removeFromQueue(at: index)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            playerManager.playNext(track)
                            playerManager.removeFromQueue(at: index)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        .tint(.accentColor)
                    }
                    .contextMenu {
                        Button {
                            playerManager.playTrack(track)
                        } label: {
                            Label("Play Now", systemImage: "play")
                        }
                        Button {
                            playerManager.playNext(track)
                            playerManager.removeFromQueue(at: index)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        Divider()
                        Button(role: .destructive) {
                            withAnimation {
                                playerManager.removeFromQueue(at: index)
                            }
                        } label: {
                            Label("Remove from Queue", systemImage: "trash")
                        }
                    }
            }
            .onMove { source, destination in
                playerManager.moveInQueue(from: source, to: destination)
            }
        } header: {
            HStack {
                Text("Up Next")
                Spacer()
                if !playerManager.queue.isEmpty {
                    EditButton()
                        .font(.caption)
                }
            }
        }
    }
    
    @ViewBuilder
    private func queueRow(for track: Track, at index: Int) -> some View {
        HStack(spacing: 12) {
            indexOrPlayingIndicator(for: index)
            
            trackThumbnail(for: track)
            
            trackDetails(for: track, at: index)
            
            Spacer()
            
            Text(track.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func indexOrPlayingIndicator(for index: Int) -> some View {
        if index == playerManager.currentIndex {
            if #available(iOS 17.0, *) {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                    .symbolEffect(.variableColor.iterative)
                    .frame(width: 20)
            } else {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
            }
        } else {
            Text("\(index + 1)")
                .foregroundColor(.secondary)
                .frame(width: 20)
        }
    }
    
    private func trackThumbnail(for track: Track) -> some View {
        let imageURL = XonoraClient.shared.getImageURL(for: track.imageUrl ?? track.album?.imageUrl, size: .thumbnail)

        return CachedAsyncImage(url: imageURL) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    private func trackDetails(for track: Track, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.name)
                .font(.body)
                .foregroundColor(index == playerManager.currentIndex ? .accentColor : .primary)
                .lineLimit(1)
            
            Text(track.artistNames)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct PlayerPickerView: View {
    @ObservedObject private var client = XonoraClient.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(client.visiblePlayers) { player in
                    Button {
                        if player.playerId != client.currentPlayer?.playerId {
                            client.currentPlayer = player
                            Task { try? await client.switchPlayer(playerId: player.playerId) }
                        }
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: ProviderBrand(provider: player.provider, type: player.type, name: player.name).icon)
                                .font(.title3)
                                .foregroundColor(ProviderBrand(provider: player.provider, type: player.type, name: player.name).color)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                    .foregroundColor(.primary)
                                Text(ProviderBrand(provider: player.provider, type: player.type, name: player.name).displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if player.playerId == client.currentPlayer?.playerId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }

                            if !player.available {
                                Text("Offline")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(!player.available)
                }
            }
            .navigationTitle("Playback Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView()
            .environmentObject(PlayerViewModel())
    }
}
