import SwiftUI
import MediaPlayer

struct PlayerControls: View {
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject private var xonoraClient = XonoraClient.shared
    @ObservedObject private var sendspinClient = SendspinClient.shared
    
    let size: ControlSize

    // Live preview of the scrub position while the user drags the progress bar.
    // Keeps the time labels in sync with the thumb without spamming seek commands.
    @State private var scrubPreview: TimeInterval?

    enum ControlSize {
        case compact
        case full
    }

    var body: some View {
        switch size {
        case .compact:
            compactControls
        case .full:
            fullControls
        }
    }
    
    private var isLocalPlayer: Bool {
        // If we are playing on this device (Sendspin), show system volume slider
        guard let currentId = xonoraClient.currentPlayer?.playerId,
              let localId = sendspinClient.clientId else {
            return false
        }
        return currentId == localId
    }

    private var compactControls: some View {
        HStack(spacing: 24) {
            Button {
                playerManager.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }

            Button {
                playerManager.togglePlayPause()
            } label: {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            Button {
                playerManager.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var fullControls: some View {
        VStack(spacing: 24) {
            // Progress bar
            VStack(spacing: 4) {
                ProgressSlider(
                    value: playerManager.currentTime,
                    range: 0...max(playerManager.duration, 1),
                    onScrub: { scrubPreview = $0 },
                    onCommit: { time in
                        playerManager.seek(to: time)
                        scrubPreview = nil
                    }
                )

                HStack {
                    Text(formatTime(scrubPreview ?? playerManager.currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("-\(formatTime(playerManager.duration - (scrubPreview ?? playerManager.currentTime)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Main controls
            HStack(spacing: 40) {
                Button {
                    playerManager.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .foregroundColor(playerManager.shuffleEnabled ? .accentColor : .secondary)
                }

                Button {
                    playerManager.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.7))
                }

                Button {
                    playerManager.togglePlayPause()
                } label: {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }

                Button {
                    playerManager.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.7))
                }

                Button {
                    playerManager.cycleRepeatMode()
                } label: {
                    repeatModeIcon
                        .font(.title3)
                        .foregroundColor(playerManager.repeatMode != .off ? .accentColor : .secondary)
                }
            }

            // Volume slider and destination
            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    if isLocalPlayer {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button {
                            Task { await xonoraClient.toggleMute() }
                        } label: {
                            Image(systemName: (xonoraClient.currentPlayer?.volumeMuted ?? false) ? "speaker.slash.fill" : "speaker.fill")
                                .font(.caption)
                                .foregroundColor((xonoraClient.currentPlayer?.volumeMuted ?? false) ? .accentColor : .secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }

                    if isLocalPlayer {
                        VolumeView()
                            .frame(height: 30) // Match standard slider height
                    } else {
                        Slider(
                            value: Binding(
                                get: { Double(playerManager.volume) },
                                set: { playerManager.setVolume(Float($0)) }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                if !editing {
                                    Task { try? await xonoraClient.setVolume(Int(playerManager.volume * 100)) }
                                }
                            }
                        )
                        .tint(.secondary)
                    }

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Playback Destination
                if let playerName = xonoraClient.currentPlayer?.name {
                    HStack(spacing: 6) {
                        Image(systemName: isLocalPlayer ? "iphone" : "speaker.wave.2.fill")
                            .font(.caption)
                        Text(playerName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var repeatModeIcon: some View {
        switch playerManager.repeatMode {
        case .off:
            Image(systemName: "repeat")
        case .all:
            Image(systemName: "repeat")
        case .one:
            Image(systemName: "repeat.1")
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }
        let t = max(0, time) // clamp negatives so remaining-time never shows "-0:-9"
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ProgressSlider: View {
    /// Current playback time, used for display when the user isn't dragging.
    let value: TimeInterval
    let range: ClosedRange<TimeInterval>
    /// Called continuously with the previewed time while dragging (no seek).
    var onScrub: ((TimeInterval) -> Void)? = nil
    /// Called once with the final time when the drag ends (performs the seek).
    var onCommit: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragValue: TimeInterval = 0

    private var displayValue: TimeInterval {
        isDragging ? dragValue : value
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4)

                // Progress track
                Capsule()
                    .fill(Color.primary)
                    .frame(width: progressWidth(in: geometry.size.width), height: 4)

                // Thumb (enlarges while dragging)
                Circle()
                    .fill(Color.primary)
                    .frame(width: isDragging ? 16 : 0, height: isDragging ? 16 : 0)
                    .offset(x: thumbOffset(in: geometry.size.width))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let percentage = max(0, min(1, gesture.location.x / geometry.size.width))
                        let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(percentage)
                        dragValue = newValue
                        // Local-only preview — do NOT seek on every frame. Seeking per
                        // frame round-trips to the server and fights the incoming time
                        // updates, which is what made dragging feel laggy/imprecise.
                        onScrub?(newValue)
                    }
                    .onEnded { _ in
                        // Commit a single seek to the released position.
                        onCommit(dragValue)
                        isDragging = false
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
        }
        .frame(height: 20)
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        let rangeSpan = range.upperBound - range.lowerBound
        guard rangeSpan > 0 else { return 0 }
        let percentage = (displayValue - range.lowerBound) / rangeSpan
        return max(0, min(totalWidth, CGFloat(percentage) * totalWidth))
    }

    private func thumbOffset(in totalWidth: CGFloat) -> CGFloat {
        progressWidth(in: totalWidth) - (isDragging ? 8 : 0)
    }
}

struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView()
        volumeView.showsVolumeSlider = true
        // Tinting is handled by system appearance mostly, but we can try to style if needed
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct PlayerControls_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            PlayerControls(playerManager: PlayerManager.shared, size: .compact)

            PlayerControls(playerManager: PlayerManager.shared, size: .full)
                .padding()
        }
    }
}
