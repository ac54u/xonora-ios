// ABOUTME: AVAudioEngine-based audio player with deep-buffer resilience
// ABOUTME: Maintains 60s ring buffer for seamless background/foreground transitions

import AVFoundation
import Accelerate
import Foundation

/// Audio player using AVAudioEngine for playback
/// Thread-safe using dedicated DispatchQueue (AVAudioEngine is not Sendable)
public final class AudioPlayer: @unchecked Sendable {
    // Audio engine components (accessed only on audioThread)
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // Decoder
    private var decoder: AudioDecoder?
    private var currentFormat: AudioFormatSpec?

    // Playback state
    private var _isPlaying: Bool = false
    private var _volume: Float = 1.0
    private var _muted: Bool = false

    // Buffering system (PCM data)
    private var pcmChunks: [Data] = []
    private var totalBufferedBytes: Int = 0
    private let bufferLock = NSLock()
    
    private var chunksInNode = 0
    
    // ============================================================
    // DEEP BUFFER — keeps 60 seconds of PCM in the playerNode so
    // background/foreground transitions never cause an audible gap.
    // ============================================================
    private let maxChunksInNode = 400           // 400 × 150ms = 60 seconds (was 12)
    private var isPlaybackStarted = false
    private var didFireFirstAudioCallback = false

    // Scheduling
    private var scheduleTimer: DispatchSourceTimer?

    // ============================================================
    // RING BUFFER — preserves PCM data across AudioPlayer stop/start
    // cycles. Never cleared, only overwritten FIFO when full.
    // ============================================================
    private var ringBuffer: [Data] = []
    private var ringBufferBytes: Int = 0
    private let ringBufferMaxSeconds: Double = 30.0 // 30 seconds of resilience

    // Configuration
    private let scheduleChunkSeconds: Double = 0.15  // 150ms chunks
    private let initialBufferSeconds: Double = 3.0   // 3s initial buffer before first play (was 0.15s)
    private let schedulerInterval: Double = 0.05     // 50ms check

    // Callback fired once (on audioThread) when the first audio buffer is scheduled to the engine.
    public var onFirstAudioScheduled: (() -> Void)?

    // Dedicated threads
    private let audioThread: DispatchQueue
    private let decodingQueue: DispatchQueue

    public var isPlaying: Bool {
        audioThread.sync { _isPlaying }
    }

    public var volume: Float {
        audioThread.sync { _volume }
    }

    public var muted: Bool {
        audioThread.sync { _muted }
    }

    public init() {
        audioThread = DispatchQueue(
            label: "com.sendspinkit.audiothread",
            qos: .userInteractive
        )
        decodingQueue = DispatchQueue(
            label: "com.sendspinkit.decoding",
            qos: .userInitiated
        )
        setupNotifications()
    }

    deinit {
        scheduleTimer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupNotifications() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.audioThread.async {
                self?.handleInterruption(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.audioThread.async {
                self?.handleRouteChange(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.audioThread.async {
                self?.handleMediaServicesReset()
            }
        }
        #endif
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // Only set category if it changed to avoid overhead
            if session.category != .playback {
                try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            }
            try session.setPreferredIOBufferDuration(0.01) // 10ms
            try session.setActive(true)
        } catch {
            // print("[AudioPlayer] Audio session error: \(error)")
        }
        #endif
    }

    private func setupEngine(format: AudioFormatSpec) {
        guard engine == nil else { return }

        let newEngine = AVAudioEngine()
        let newPlayerNode = AVAudioPlayerNode()
        newPlayerNode.volume = _volume

        newEngine.attach(newPlayerNode)

        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(format.channels),
            interleaved: false
        )
        
        if let inputFormat = inputFormat {
            newEngine.connect(newPlayerNode, to: newEngine.mainMixerNode, format: inputFormat)
        }

        engine = newEngine
        playerNode = newPlayerNode
    }

    private func startEngine() {
        guard let engine = engine else { return }
        
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                // print("[AudioPlayer] Engine start error: \(error)")
            }
        }
        
        if let playerNode = playerNode, !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func stopEngine() {
        playerNode?.stop()
        engine?.stop()
    }

    private func teardownEngine() {
        stopEngine()
        engine = nil
        playerNode = nil
        decoder = nil
        currentFormat = nil
    }

    // MARK: - Public Interface

    public func start(format: AudioFormatSpec, codecHeader: Data?) throws {
        try audioThread.sync {
            if _isPlaying, currentFormat == format {
                return
            }

            stopInternal()

            savedCodecHeader = codecHeader
            decoder = try AudioDecoderFactory.create(
                codec: format.codec,
                sampleRate: format.sampleRate,
                channels: format.channels,
                bitDepth: format.bitDepth,
                header: codecHeader
            )
            currentFormat = format

            didFireFirstAudioCallback = false

            setupAudioSession()
            setupEngine(format: format)
            // Engine is NOT started here — it will be started by scheduleChunk()
            // when the first audio buffer is actually scheduled to the playerNode.
            // This avoids playing silence while the initial buffer accumulates.
            startScheduleTimer()

            _isPlaying = true
        }
    }

    public func decode(_ data: Data) throws -> Data {
        try audioThread.sync {
            guard let decoder = decoder else {
                throw AudioPlayerError.notStarted
            }
            return try decoder.decode(data)
        }
    }

    public func playPCM(_ pcmData: Data) {
        bufferLock.lock()
        pcmChunks.append(pcmData)
        totalBufferedBytes += pcmData.count
        
        // Also append to the resilience ring buffer (FIFO overwrite when full)
        ringBuffer.append(pcmData)
        ringBufferBytes += pcmData.count
        trimRingBuffer()
        bufferLock.unlock()
    }
    
    /// Trim ring buffer to max duration, dropping oldest data first
    private func trimRingBuffer() {
        guard let format = currentFormat else { return }
        let bytesPerSecond = format.sampleRate * format.channels * (effectiveBitDepth(for: format) / 8)
        let maxBytes = Int(ringBufferMaxSeconds * Double(bytesPerSecond))
        
        while ringBufferBytes > maxBytes && !ringBuffer.isEmpty {
            let oldest = ringBuffer.removeFirst()
            ringBufferBytes -= oldest.count
        }
    }
    
    /// Drain ring buffer content as a single Data blob (thread-safe, called on audioThread)
    private func drainRingBuffer() -> Data {
        bufferLock.lock()
        let allData = ringBuffer.reduce(into: Data()) { $0.append($1) }
        // Don't clear the ring buffer — keep it for future foreground transitions
        bufferLock.unlock()
        return allData
    }

    public func stop() {
        audioThread.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func stopInternal() {
        scheduleTimer?.cancel()
        scheduleTimer = nil

        teardownEngine()

        bufferLock.lock()
        pcmChunks.removeAll(keepingCapacity: true)
        totalBufferedBytes = 0
        chunksInNode = 0
        isPlaybackStarted = false
        didFireFirstAudioCallback = false
        // ringBuffer is NOT cleared — it survives stop/start for seamless resume
        bufferLock.unlock()

        _isPlaying = false
        // Don't deactivate session here to avoid -50 errors on immediate restart
    }

    public func setVolume(_ volume: Float) {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            let clamped = max(0.0, min(1.0, volume))
            self._volume = clamped
            self.playerNode?.volume = self._muted ? 0.0 : clamped
        }
    }

    public func setMute(_ muted: Bool) {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            self._muted = muted
            self.playerNode?.volume = muted ? 0.0 : self._volume
        }
    }

    public func pause() {
        audioThread.async { [weak self] in
            self?.playerNode?.pause()
        }
    }

    public func resume() {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            
            // ============================================================
            // Step 1: Reset scheduled-buffer counter.
            // During app suspension the engine was stopped; completion
            // callbacks for previously-scheduled buffers may not have fired.
            // Resetting forces the scheduler to re-fill from scratch.
            // ============================================================
            bufferLock.lock()
            chunksInNode = 0
            let hasPendingData = totalBufferedBytes > 0
            let hasRingData = ringBufferBytes > 0
            bufferLock.unlock()
            
            // ============================================================
            // Step 2: Immediately drain resilience ring buffer into the
            // playerNode. This provides seamless audio while the WebSocket
            // reconnects in the background.
            // ============================================================
            if hasRingData {
                self.scheduleAllRingBufferData()
            } else if hasPendingData {
                self.scheduleBufferedAudio()
            }
            
            // ============================================================
            // Step 3: Restart engine and playback
            // ============================================================
            if let engine = self.engine, !engine.isRunning {
                self.startEngine()
            }
            self.playerNode?.play()
        }
    }
    
    /// Schedule ALL ring buffer data into the playerNode at once.
    /// Called on audioThread during resume to fill the pipeline instantly.
    private func scheduleAllRingBufferData() {
        guard let format = currentFormat else { return }
        
        let effectiveBitDepth = self.effectiveBitDepth(for: format)
        let bytesPerFrame = format.channels * (effectiveBitDepth / 8)
        let bytesPerSecond = format.sampleRate * bytesPerFrame
        let chunkBytes = Int(scheduleChunkSeconds * Double(bytesPerSecond))
        
        let data = drainRingBuffer()
        var offset = 0
        
        bufferLock.lock()
        chunksInNode = 0
        bufferLock.unlock()
        
        while offset + chunkBytes <= data.count && chunksInNode < maxChunksInNode {
            let chunk = data.subdata(in: offset..<offset + chunkBytes)
            offset += chunkBytes
            scheduleChunk(chunk, format: format)
            bufferLock.lock()
            chunksInNode += 1
            bufferLock.unlock()
        }
    }
    
    public func getCurrentTime() -> TimeInterval {
        audioThread.sync {
            guard let node = playerNode,
                  let lastRenderTime = node.lastRenderTime,
                  let playerTime = node.playerTime(forNodeTime: lastRenderTime) else {
                return 0
            }
            return Double(playerTime.sampleTime) / playerTime.sampleRate
        }
    }

    // MARK: - Scheduling

    private func startScheduleTimer() {
        scheduleTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: audioThread)
        timer.schedule(deadline: .now() + 0.1, repeating: schedulerInterval)
        timer.setEventHandler { [weak self] in
            self?.scheduleBufferedAudio()
        }
        timer.resume()
        scheduleTimer = timer
    }

    private func scheduleBufferedAudio() {
        guard let format = currentFormat else { return }

        let effectiveBitDepth = self.effectiveBitDepth(for: format)
        let bytesPerFrame = format.channels * (effectiveBitDepth / 8)
        let bytesPerSecond = format.sampleRate * bytesPerFrame
        let chunkBytes = Int(scheduleChunkSeconds * Double(bytesPerSecond))
        let initialBufferBytes = Int(initialBufferSeconds * Double(bytesPerSecond))

        bufferLock.lock()

        // Wait for initial buffer
        if !isPlaybackStarted {
            if totalBufferedBytes >= initialBufferBytes {
                isPlaybackStarted = true
            } else {
                bufferLock.unlock()
                return
            }
        }

        // Schedule chunks
        while totalBufferedBytes >= chunkBytes && chunksInNode < maxChunksInNode {
            // Aggregate chunks into a single Data block for the requested chunk size
            var dataToSchedule = Data(capacity: chunkBytes)
            while dataToSchedule.count < chunkBytes && !pcmChunks.isEmpty {
                let first = pcmChunks.removeFirst()
                let needed = chunkBytes - dataToSchedule.count
                
                if first.count <= needed {
                    dataToSchedule.append(first)
                    totalBufferedBytes -= first.count
                } else {
                    // Split the chunk
                    dataToSchedule.append(first.prefix(needed))
                    let remaining = first.dropFirst(needed)
                    pcmChunks.insert(Data(remaining), at: 0)
                    totalBufferedBytes -= needed
                }
            }
            
            chunksInNode += 1
            bufferLock.unlock()

            scheduleChunk(dataToSchedule, format: format)

            bufferLock.lock()
        }

        bufferLock.unlock()
    }

    private func scheduleChunk(_ data: Data, format: AudioFormatSpec) {
        guard let playerNode = playerNode else { return }
        
        guard let bufferFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(format.channels),
            interleaved: false
        ) else {
            return
        }

        let effectiveBitDepth = self.effectiveBitDepth(for: format)
        let bytesPerFrame = format.channels * (effectiveBitDepth / 8)
        let frameCount = data.count / bytesPerFrame

        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let floatChannelData = buffer.floatChannelData else { return }

        if effectiveBitDepth == 16 {
            convertInt16ToFloat32(data, into: floatChannelData, frameCount: frameCount, channels: format.channels)
        } else {
            convertInt32ToFloat32(data, into: floatChannelData, frameCount: frameCount, channels: format.channels)
        }
        
        if let engine = engine, !engine.isRunning {
            startEngine()
        } else if !playerNode.isPlaying {
            playerNode.play()
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            guard let self = self else { return }
            self.bufferLock.lock()
            self.chunksInNode = max(0, self.chunksInNode - 1)
            self.bufferLock.unlock()
        }

        if !didFireFirstAudioCallback {
            didFireFirstAudioCallback = true
            DispatchQueue.global().async { [weak self] in
                self?.onFirstAudioScheduled?()
            }
        }
    }

    private func effectiveBitDepth(for format: AudioFormatSpec) -> Int {
        switch format.codec {
        case .flac, .opus: return 32
        case .pcm: return format.bitDepth == 24 ? 32 : format.bitDepth
        }
    }

    private func convertInt16ToFloat32(
        _ data: Data,
        into floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channels: Int
    ) {
        data.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }

            if channels == 2 {
                var leftInt16 = [Int16](repeating: 0, count: frameCount)
                var rightInt16 = [Int16](repeating: 0, count: frameCount)

                for i in 0..<frameCount {
                    leftInt16[i] = int16Ptr[i * 2]
                    rightInt16[i] = int16Ptr[i * 2 + 1]
                }

                var scale: Float = 1.0 / 32768.0
                vDSP_vflt16(leftInt16, 1, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vflt16(rightInt16, 1, floatChannelData[1], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[0], 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[1], 1, &scale, floatChannelData[1], 1, vDSP_Length(frameCount))
            } else {
                var scale: Float = 1.0 / 32768.0
                vDSP_vflt16(int16Ptr, 1, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[0], 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
            }
        }
    }

    private func convertInt32ToFloat32(
        _ data: Data,
        into floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channels: Int
    ) {
        data.withUnsafeBytes { rawBuffer in
            guard let int32Ptr = rawBuffer.bindMemory(to: Int32.self).baseAddress else { return }

            if channels == 2 {
                var leftInt32 = [Int32](repeating: 0, count: frameCount)
                var rightInt32 = [Int32](repeating: 0, count: frameCount)

                for i in 0..<frameCount {
                    leftInt32[i] = int32Ptr[i * 2]
                    rightInt32[i] = int32Ptr[i * 2 + 1]
                }

                var leftFloat = [Float](repeating: 0, count: frameCount)
                var rightFloat = [Float](repeating: 0, count: frameCount)

                vDSP_vflt32(leftInt32, 1, &leftFloat, 1, vDSP_Length(frameCount))
                vDSP_vflt32(rightInt32, 1, &rightFloat, 1, vDSP_Length(frameCount))

                var scale: Float = 1.0 / Float(Int32.max)
                vDSP_vsmul(leftFloat, 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(rightFloat, 1, &scale, floatChannelData[1], 1, vDSP_Length(frameCount))
            } else {
                var floatBuffer = [Float](repeating: 0, count: frameCount)
                vDSP_vflt32(int32Ptr, 1, &floatBuffer, 1, vDSP_Length(frameCount))

                var scale: Float = 1.0 / Float(Int32.max)
                vDSP_vsmul(floatBuffer, 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            playerNode?.pause()
        case .ended:
            // Always try to resume — even without .shouldResume flag,
            // because the app's audio session may have been interrupted
            // by a transient interruption (e.g., Siri, alarm).
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if engine?.isRunning == false {
                    try engine?.start()
                }
                playerNode?.play()
            } catch {
                // If engine failed to restart, rebuild it from ring buffer
                if let format = currentFormat {
                    teardownEngine()
                    setupAudioSession()
                    setupEngine(format: format)
                    resume()
                }
            }
        @unknown default: break
        }
        #endif
    }

    private func handleRouteChange(_ notification: Notification) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged — pause to avoid speaker blast
            playerNode?.pause()
        case .newDeviceAvailable:
            // New output available (e.g., Bluetooth connected) — resume if was playing
            if _isPlaying {
                playerNode?.play()
            }
        default:
            break
        }
        #endif
    }

    private var savedCodecHeader: Data?

    internal func setCodecHeader(_ header: Data?) {
        savedCodecHeader = header
    }

    private func handleMediaServicesReset() {
        let wasPlaying = _isPlaying
        let savedFormat = currentFormat

        teardownEngine()

        if wasPlaying, let format = savedFormat {
            decoder = try? AudioDecoderFactory.create(
                codec: format.codec,
                sampleRate: format.sampleRate,
                channels: format.channels,
                bitDepth: format.bitDepth,
                header: savedCodecHeader
            )
            currentFormat = savedFormat
            setupAudioSession()
            setupEngine(format: format)
            resume()
            startScheduleTimer()
        }
    }
}

public enum AudioPlayerError: Error {
    case notStarted
    case decodingFailed
    case bufferCreationFailed
    case unsupportedFormat
}
