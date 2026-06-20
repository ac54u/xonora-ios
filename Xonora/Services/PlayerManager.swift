import Foundation
import AVFoundation
import MediaPlayer
import Combine

enum PlaybackState: Equatable {
    case stopped
    case playing
    case paused
    case loading
    case error(String)
}

enum RepeatMode: Int {
    case off = 0
    case all = 1
    case one = 2
}

@MainActor
class PlayerManager: ObservableObject {
    @Published var playbackState: PlaybackState = .stopped
    @Published var currentTrack: Track?
    @Published var currentTime: TimeInterval = 0 {
        didSet {
            lastUpdateTime = Date()
        }
    }
    @Published var duration: TimeInterval = 0
    @Published var lastUpdateTime: Date = Date()
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Float = 1.0
    @Published var currentSource: String?
    @Published var sleepTimerActive = false
    @Published var sleepTimerEndDate: Date?
    private var sleepTimerTask: Task<Void, Never>?

    private var progressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastTrackId: String?
    private var cachedArtwork: MPMediaItemArtwork?

    // Prevent queue advancement race conditions
    private var isUserInitiatedPlay = false
    private var userPlayDebounceTask: Task<Void, Never>?

    // Drift correction: use server-reported time as authoritative source
    private var serverTime: TimeInterval = 0
    private var serverTimeReceivedAt: Date = Date()
    private var localTimeOffset: TimeInterval = 0 // local clock drift between timer ticks

    static let shared = PlayerManager()

    init() {
        // Setup remote commands and notifications asynchronously to avoid blocking init
        Task {
            await setupRemoteCommandCenter()
            await setupNotifications()
        }

        SendspinClient.shared.$isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isBuffering in
                guard let self = self else { return }
                if !isBuffering && self.playbackState == .loading {
                    self.playbackState = .playing
                    self.startProgressTimer()
                    print("[PlayerManager] Playback started, progress timer enabled")
                }
            }
            .store(in: &cancellables)
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        localTimeOffset = 0

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                if self.playbackState == .playing {
                    self.objectWillChange.send()

                    // Drift-corrected time: start from last server time, add wall-clock delta
                    let elapsedSinceServer = Date().timeIntervalSince(self.serverTimeReceivedAt)
                    let correctedTime = self.serverTime + elapsedSinceServer + self.localTimeOffset

                    // Only apply if the correction is reasonable (avoid jumps > 2s)
                    let diff = abs(correctedTime - self.currentTime)
                    if diff > 2.0 {
                        self.currentTime = correctedTime
                    } else {
                        self.currentTime = correctedTime
                    }

                    if self.duration > 0 && self.currentTime >= self.duration {
                        // Server will handle track end
                    }

                    if Int(self.currentTime) % 5 == 0 {
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.next()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.previous()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .queueUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self, let userInfo = notification.userInfo else { return }

                // Ignore events during user-initiated play to prevent race conditions
                if self.isUserInitiatedPlay {
                    // Still update duration if available
                    if let currentItem = userInfo["current_item"] as? [String: Any],
                       let duration = currentItem["duration"] as? Int {
                        self.duration = TimeInterval(duration)
                    }
                    return
                }

                if let elapsed = userInfo["elapsed_time"] as? Double {
                    self.serverTime = elapsed
                    self.serverTimeReceivedAt = Date()
                    self.currentTime = elapsed
                }

                // Detect server auto-advance: an idle/stopped state arriving in the SAME
                // event that also carries a *different* current_item track means the server
                // is moving to the next track, not really stopping. We must NOT tear down the
                // Sendspin stream then — stopPlayback() disconnects the client and kills audio,
                // leaving the UI "playing" (progress bar moving) but silent.
                let incomingTrackURI = (userInfo["current_item"] as? [String: Any])
                    .flatMap { $0["media_item"] as? [String: Any] }
                    .flatMap { $0["uri"] as? String }
                let isAutoAdvance = incomingTrackURI != nil && incomingTrackURI != self.currentTrack?.uri

                if let stateStr = userInfo["state"] as? String {
                    if stateStr == "playing" {
                        self.playbackState = .playing
                        self.startProgressTimer()
                        SendspinClient.shared.resumePlayback()
                        self.postPlaybackStateChange()
                    } else if stateStr == "paused" {
                        self.playbackState = .paused
                        self.stopProgressTimer()
                        SendspinClient.shared.pausePlayback()
                        self.postPlaybackStateChange()
                    } else if stateStr == "idle" {
                        if self.playbackState == .playing && !isAutoAdvance {
                            self.handleTrackEnded()
                            SendspinClient.shared.stopPlayback()
                        }
                        self.postPlaybackStateChange()
                    } else if !isAutoAdvance {
                        self.playbackState = .stopped
                        self.stopProgressTimer()
                        SendspinClient.shared.stopPlayback()
                        self.postPlaybackStateChange()
                    }
                }

                // Handle current item updates (auto-advance)
                if let currentItem = userInfo["current_item"] as? [String: Any] {
                    // Update duration
                    if let duration = currentItem["duration"] as? Int {
                        self.duration = TimeInterval(duration)
                    } else if let duration = currentItem["duration"] as? Double {
                        self.duration = duration
                    }

                    // Update current track if it changed
                    if let mediaItemDict = currentItem["media_item"] as? [String: Any] {
                        do {
                            let data = try JSONSerialization.data(withJSONObject: mediaItemDict)
                            let track = try JSONDecoder().decode(Track.self, from: data)
                            let oldTrack = self.currentTrack
                            if oldTrack?.uri != track.uri {
                                print("[PlayerManager] Server advanced to next track: \(track.name)")
                                self.currentTrack = track
                                self.currentTime = 0
                                // Reset lastTrackId to trigger artwork reload
                                self.lastTrackId = nil
                                // Sync queue index
                                if let idx = self.queue.firstIndex(where: { $0.uri == track.uri }) {
                                    self.currentIndex = idx
                                }
                                // If track ended naturally and server auto-advanced but the
                                // stream isn't marked playing, resume it (covers the case where
                                // idle and the next track arrive in separate events).
                                if oldTrack != nil && self.playbackState != .playing {
                                    self.playbackState = .playing
                                    self.startProgressTimer()
                                    SendspinClient.shared.resumePlayback()
                                    self.postPlaybackStateChange()
                                }
                            }
                        } catch {
                            print("[PlayerManager] Failed to decode track from server: \(error)")
                        }
                    }
                }

                self.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
    }

    private func handleTrackEnded() {
        // Don't auto-advance - let server handle queue
        // We only update UI state here
        playbackState = .stopped
        stopProgressTimer()
        print("[PlayerManager] Track ended")

        if sleepTimerActive && sleepTimerEndDate == nil {
            pause()
            sleepTimerActive = false
            postPlaybackStateChange()
        }
    }



    // MARK: - Playback Control

    private func postPlaybackStateChange() {
        NotificationCenter.default.post(name: .playbackStateChanged, object: nil)
    }

    func playTrack(_ track: Track, fromQueue tracks: [Track]? = nil, sourceName: String? = nil) {
        if let tracks = tracks {
            queue = tracks
            currentIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        } else {
            // If no queue context provided, play just this track
            queue = [track]
            currentIndex = 0
        }
        
        self.currentSource = sourceName

        guard SendspinClient.shared.isConnected else {
            playbackState = .error(NSLocalizedString("Sendspin not connected. Please enable it in Settings.", comment: "Playback error"))
            return
        }

        print("[PlayerManager] Playing: \(track.name)")

        // Force Shuffle OFF for direct track selection to ensure the selected track plays
        self.shuffleEnabled = false
        Task { try? await XonoraClient.shared.setShuffle(enabled: false) }

        // Sync Repeat Mode to ensure server matches client state (fixes stuck repeat issues)
        let modeString: String
        switch repeatMode {
        case .off: modeString = "off"
        case .all: modeString = "all"
        case .one: modeString = "one"
        }
        Task { try? await XonoraClient.shared.setRepeat(mode: modeString) }

        // Set debounce flag to ignore server events temporarily
        isUserInitiatedPlay = true
        userPlayDebounceTask?.cancel()
        userPlayDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await MainActor.run {
                self.isUserInitiatedPlay = false
            }
        }

        currentTrack = track
        currentTime = 0
        duration = track.duration ?? 0
        playbackState = .loading
        postPlaybackStateChange()

        SendspinClient.shared.stopPlayback()
        stopProgressTimer()
        Task {
            await self.updateNowPlayingInfoAsync()
        }

        // Prepare URIs to play (current track + subsequent queue items)
        let uris: [String]
        if !queue.isEmpty && currentIndex < queue.count {
            uris = Array(queue[currentIndex..<queue.count]).map { $0.uri }
        } else {
            uris = [track.uri]
        }

        // Tell server to play this track
        Task {
            do {
                try await XonoraClient.shared.playMedia(uris: uris)
            } catch {
                print("[PlayerManager] Failed to send play command: \(error)")
                
                // Suppress "Request timeout" error if it happens, as it often means the server 
                // processed the command but the acknowledgement was lost/delayed, while music plays fine.
                let nsError = error as NSError
                if nsError.code == -1 && nsError.userInfo[NSLocalizedDescriptionKey] as? String == "Request timeout" {
                    print("[PlayerManager] Suppressing Request timeout error.")
                    return
                }
                
                await MainActor.run {
                    self.playbackState = .error(String.localizedStringWithFormat(NSLocalizedString("Failed to play: %@", comment: "Playback error"), error.localizedDescription))
                }
            }
        }
    }

    func play() {
        Task {
            try? await XonoraClient.shared.play()
        }
    }

    func pause() {
        Task {
            try? await XonoraClient.shared.pause()
        }
    }

    func togglePlayPause() {
        Task {
            try? await XonoraClient.shared.playPause()
        }
    }

    func stop() {
        Task {
            try? await XonoraClient.shared.stop()
        }
        currentTrack = nil
        currentTime = 0
        duration = 0
        playbackState = .stopped
        stopProgressTimer()
        clearNowPlayingInfo()
        postPlaybackStateChange()
    }

    func next() {
        guard !queue.isEmpty else { return }

        // Always advance sequentially. Shuffle is handled by reordering the queue itself.
        currentIndex = (currentIndex + 1) % queue.count

        let nextTrack = queue[currentIndex]
        playTrack(nextTrack, fromQueue: queue, sourceName: currentSource)
    }

    func previous() {
        // If we are more than 3 seconds into the track, restart it
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        guard !queue.isEmpty else { return }

        // Check if we are at the start of the queue
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            // Wrap around to the last track
            currentIndex = queue.count - 1
        }

        let previousTrack = queue[currentIndex]
        playTrack(previousTrack, fromQueue: queue, sourceName: currentSource)
    }

    func seek(to time: TimeInterval) {
        if SendspinClient.shared.isConnected {
            Task { try? await XonoraClient.shared.seek(position: time) }
        }
        currentTime = time
        Task {
            await self.updateNowPlayingInfoAsync()
        }
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        if SendspinClient.shared.isConnected {
            Task { try? await XonoraClient.shared.setVolume(Int(newVolume * 100)) }
        }
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        Task { try? await XonoraClient.shared.setShuffle(enabled: shuffleEnabled) }
        
        guard !queue.isEmpty else { return }
        
        if shuffleEnabled {
            // Shuffle the queue, ensuring current track stays playing
            var tracks = queue
            if let current = currentTrack, let idx = tracks.firstIndex(where: { $0.id == current.id }) {
                tracks.remove(at: idx)
                tracks.shuffle()
                tracks.insert(current, at: 0)
                currentIndex = 0
            } else {
                tracks.shuffle()
                currentIndex = 0
            }
            queue = tracks
        } else {
            // Restore album order (approximate by sorting)
            var tracks = queue
            tracks.sort {
                let disc1 = $0.discNumber ?? 1
                let disc2 = $1.discNumber ?? 1
                if disc1 != disc2 { return disc1 < disc2 }
                return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0)
            }
            queue = tracks
            
            // Update currentIndex to match current track's new position
            if let current = currentTrack {
                currentIndex = queue.firstIndex(where: { $0.id == current.id }) ?? 0
            }
        }
    }

    func cycleRepeatMode() {
        let nextRaw = (repeatMode.rawValue + 1) % 3
        repeatMode = RepeatMode(rawValue: nextRaw) ?? .off
        
        let modeString: String
        switch repeatMode {
        case .off: modeString = "off"
        case .all: modeString = "all"
        case .one: modeString = "one"
        }
        
        Task { try? await XonoraClient.shared.setRepeat(mode: modeString) }
    }

    // MARK: - Queue Management

    func addToQueue(_ track: Track) {
        queue.append(track)
    }

    func addToQueue(_ tracks: [Track]) {
        queue.append(contentsOf: tracks)
    }

    func playNext(_ track: Track) {
        queue.insert(track, at: currentIndex + 1)
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            if queue.count > 1 {
                currentIndex = min(currentIndex, queue.count - 2)
            }
        }
        queue.remove(at: index)
        Task { await XonoraClient.shared.deleteQueueItem(at: index) }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let movedTrack = queue[sourceIndex]
        queue.move(fromOffsets: source, toOffset: destination)
        if let current = currentTrack {
            currentIndex = queue.firstIndex(where: { $0.id == current.id }) ?? 0
        }
        let newIndex = queue.firstIndex(where: { $0.id == movedTrack.id }) ?? sourceIndex
        let posShift = newIndex - sourceIndex
        Task { await XonoraClient.shared.moveQueueItem(matchingURI: movedTrack.uri, posShift: posShift) }
    }

    func clearQueue() {
        queue.removeAll()
        currentIndex = 0
        Task { await XonoraClient.shared.stopQueue() }
    }

    func setSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        sleepTimerActive = true
        sleepTimerEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes * 60_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = self, self.sleepTimerActive else { return }
                if self.isPlaying {
                    self.pause()
                }
                self.sleepTimerActive = false
                self.sleepTimerEndDate = nil
            }
        }
    }

    func setSleepTimerEndOfTrack() {
        sleepTimerTask?.cancel()
        sleepTimerActive = true
        sleepTimerEndDate = nil
        // Will be handled by track end detection
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerActive = false
        sleepTimerEndDate = nil
    }

    var sleepTimerDescription: String {
        guard sleepTimerActive, let endDate = sleepTimerEndDate else {
            return sleepTimerActive ? "End of Track" : ""
        }
        let remaining = max(0, endDate.timeIntervalSinceNow)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: NSLocalizedString("Sleep: %d:%02d", comment: "Sleep timer countdown"), minutes, seconds)
    }

    func playAlbum(_ tracks: [Track], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let albumName = tracks[index].album?.name
        queue = tracks
        currentIndex = index
        playTrack(tracks[index], fromQueue: tracks, sourceName: albumName)
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        Task { await updateNowPlayingInfoAsync() }
    }

    private func clearNowPlayingInfo() {
        lastTrackId = nil
        cachedArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlayingInfoAsync() async {
        guard let track = currentTrack else { return }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.name
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artistNames
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album?.name ?? ""

        await MainActor.run {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = self.duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.playbackState == .playing ? 1.0 : 0.0
        }

        if track.id != lastTrackId {
            await MainActor.run {
                self.lastTrackId = track.id
                self.cachedArtwork = nil
            }

            if let imageURLString = track.imageUrl ?? track.album?.imageUrl,
               let imageURL = XonoraClient.shared.getImageURL(for: imageURLString, size: .medium) {
                let artwork = await loadArtworkAsync(from: imageURL, trackId: track.id)
                if let artwork = artwork {
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                }
            }
        } else {
            let artwork = await MainActor.run { self.cachedArtwork }
            if let artwork = artwork {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
        }

        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }

    private func loadArtworkAsync(from url: URL, trackId: String) async -> MPMediaItemArtwork? {
        if let cachedImage = await ImageCache.shared.image(for: url) {
            let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
            await MainActor.run {
                guard self.currentTrack?.id == trackId else { return }
                self.cachedArtwork = artwork
            }
            return artwork
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }

            await ImageCache.shared.setImage(image, for: url)

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                guard self.currentTrack?.id == trackId else { return }
                self.cachedArtwork = artwork
            }
            return artwork
        } catch {
            print("[PlayerManager] Failed to load artwork: \(error)")
            return nil
        }
    }

    // MARK: - State Helpers

    var isPlaying: Bool {
        if case .playing = playbackState {
            return true
        }
        return false
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
}
