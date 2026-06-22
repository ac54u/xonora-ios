import Foundation
import Combine
import SendspinKit
import UIKit

// Facade for SendspinKit to match the app's expectation
// Adapts the modern SendspinKit actor-based client to the app's ObservableObject requirements

@MainActor
class SendspinClient: ObservableObject {
    @Published var isConnected = false
    @Published var isBuffering = false
    @Published var bufferProgress: Double = 0.0
    @Published var connectionError: String?
    @Published var playerName: String = UIDevice.current.name
    @Published var clientId: String?
    
    private let playerNameKey = "SendspinPlayerName"
    private var lastHost: String?
    private var lastPort: UInt16?
    private var lastScheme: String?
    private var lastAccessToken: String?
    
    // Reconnection logic
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTask: Task<Void, Never>?
    
    // Internal client from SendspinKit
    private var client: SendspinKit.SendspinClient?
    private var eventTask: Task<Void, Never>?
    
    static let shared = SendspinClient()
    
    private init() {
        // Prefer the Keychain-persisted name (survives reinstall), then UserDefaults,
        // then the device default. iOS 16+ returns a generic "iPhone" for
        // UIDevice.name, so without this the user's custom name was lost on reinstall.
        if let keychainName = KeychainHelper.shared.getPlayerName(), !keychainName.isEmpty {
            self.playerName = keychainName
        } else if let savedName = UserDefaults.standard.string(forKey: playerNameKey) {
            self.playerName = savedName
        }
        
        // Auto-reconnect on foreground if needed
        Task { @MainActor in
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                if !self.isConnected && self.lastHost != nil {
                    self.safeLog("[SendspinClient] App foregrounded, checking connection...")
                    // Reset attempts to give it a fresh try
                    self.reconnectAttempts = 0
                    self.attemptReconnect()
                }
            }
        }
    }
    
    /// A stable client id that survives reinstalls (persisted in the Keychain),
    /// seeded once from the vendor UUID. Using the raw vendor UUID directly caused a
    /// brand-new player to register on every reinstall.
    var stableClientId: String {
        KeychainHelper.shared.getOrCreateClientId(
            seedIfMissing: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )
    }

    /// The Music Assistant Universal Player ID. MA computes this as "up" + lowercase
    /// UUID without dashes.
    var universalPlayerId: String {
        return "up" + stableClientId.lowercased().replacingOccurrences(of: "-", with: "")
    }

    func updatePlayerName(_ name: String) {
        self.playerName = name
        UserDefaults.standard.set(name, forKey: playerNameKey)
        KeychainHelper.shared.savePlayerName(name)

        // Reconnect if we have connection details
        if let host = lastHost, let port = lastPort, let scheme = lastScheme {
            connect(to: host, port: port, scheme: scheme, accessToken: lastAccessToken)
        }
    }
    
    func connect(to host: String, port: UInt16 = 8927, scheme: String = "ws", accessToken: String? = nil) {
        self.lastHost = host
        self.lastPort = port
        self.lastScheme = scheme
        self.lastAccessToken = accessToken
        
        // Reset reconnection state for fresh manual connection
        self.reconnectAttempts = 0
        self.reconnectTask?.cancel()

        let urlString = "\(scheme)://\(host):\(port)/sendspin"
        self.safeLog("[SendspinClient] Connecting to: \(urlString)")
        self.safeLog("[SendspinClient] Access token provided: \(accessToken != nil)")
        self.safeLog("[SendspinClient] Access token length: \(accessToken?.count ?? 0)")

        guard let url = URL(string: urlString) else {
            self.connectionError = String.localizedStringWithFormat(NSLocalizedString("Invalid URL: %@", comment: "Connection error"), urlString)
            self.safeLog("[SendspinClient] ERROR: Invalid URL")
            return
        }

        disconnectInternal(keepConfig: true)

        // Create configuration for the client
        // Only advertise 48kHz support to force server-side resampling if needed
        let playerConfig = PlayerConfiguration(
            bufferCapacity: 8 * 1024 * 1024, // 8MB buffer (~30s at 48kHz/16-bit/stereo)
            supportedFormats: [
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16),
                AudioFormatSpec(codec: .flac, channels: 2, sampleRate: 48000, bitDepth: 16)
            ]
        )

        let clientName = self.playerName
        // Stable across reinstalls so we keep the SAME server player_id.
        let clientId = self.stableClientId
        self.clientId = clientId
        // self.playerName is already set

        self.safeLog("[SendspinClient] Client ID: \(clientId)")
        self.safeLog("[SendspinClient] Client Name: \(clientName)")

        let client = SendspinKit.SendspinClient(
            clientId: clientId,
            name: clientName,
            roles: [.playerV1],
            playerConfig: playerConfig,
            accessToken: accessToken
        )

        self.client = client

        // Start listening to events
        eventTask = Task {
            for await event in client.events {
                handleEvent(event)
            }
        }

        Task {
            do {
                self.safeLog("[SendspinClient] Starting connection...")
                try await client.connect(to: url)
                self.safeLog("[SendspinClient] Connection initiated successfully")
            } catch {
                self.safeLog("[SendspinClient] Connection error: \(error)")
                self.connectionError = String.localizedStringWithFormat(NSLocalizedString("Connection failed: %@", comment: "Connection error"), error.localizedDescription)
                self.isConnected = false
                self.attemptReconnect()
            }
        }
    }
    
    func disconnect() {
        disconnectInternal(keepConfig: false)
    }
    
    private func disconnectInternal(keepConfig: Bool) {
        reconnectTask?.cancel()
        if !keepConfig {
            // Prevent auto-reconnect if user explicitly disconnected
            reconnectAttempts = maxReconnectAttempts
        }
        
        eventTask?.cancel()
        Task {
            await client?.disconnect()
            self.client = nil
        }
        isConnected = false
        isBuffering = false
    }
    
    private func attemptReconnect() {
        guard let host = lastHost, let port = lastPort, let scheme = lastScheme else { return }
        
        guard reconnectAttempts < maxReconnectAttempts else {
            self.safeLog("[SendspinClient] Max reconnection attempts reached")
            self.connectionError = NSLocalizedString("Failed to reconnect after multiple attempts", comment: "Connection error")
            return
        }
        
        reconnectAttempts += 1
        let delay = Double(reconnectAttempts) * 2.0
        self.safeLog("[SendspinClient] Will attempt reconnect #\(reconnectAttempts) in \(delay) seconds...")
        
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            self.safeLog("[SendspinClient] Attempting reconnection...")
            self.connect(to: host, port: port, scheme: scheme, accessToken: self.lastAccessToken)
        }
    }
    
    private func handleEvent(_ event: ClientEvent) {
        // safeLog("[SendspinClient] Event received: \(event)")
        switch event {
        case .serverConnected(let info):
            // safeLog("[SendspinClient] Connected to \(info.name)")
            self.isConnected = true
            self.connectionError = nil
            self.reconnectAttempts = 0 // Reset on success

        case .streamStarted(let format):
            // safeLog("[SendspinClient] Stream started: \(format)")
            self.isBuffering = true
            // Simulate buffering progress for UI
            Task {
                for i in 1...10 {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    self.bufferProgress = Double(i) / 10.0
                }
                self.isBuffering = false
            }

        case .streamEnded:
            // safeLog("[SendspinClient] Stream ended")
            self.isBuffering = false
            self.bufferProgress = 0.0

        case .error(let msg):
            // safeLog("[SendspinClient] Error: \(msg)")
            self.connectionError = msg
            // If error occurs, we assume connection is dead or compromised
            // However, SendspinKit might auto-recover or stay connected?
            // Usually fatal errors come here.
            // If connection timeout, we definitely want to reconnect.
            if msg.contains("Connection timeout") || msg.contains("disconnected") || !isConnected {
                self.isConnected = false
                self.attemptReconnect()
            }

        default:
            // safeLog("[SendspinClient] Unhandled event: \(event)")
            break
        }
    }

    private func safeLog(_ message: String, level: LogLevel = .info) {
        let logMessage = message.count > 1000 ? String(message.prefix(1000)) + "... (truncated)" : message
        print("[\(level.rawValue)] [SendspinClient] \(logMessage)")
        AppLogger.shared.log(logMessage, level: level, category: "SendspinClient")
    }
    
    // Playback controls (proxied to client if supported, or handled via server commands)
    // Note: Sendspin is a passive player. "Resume" usually means "Unmute" or "Start Engine" locally.
    // The Kit handles the engine automatically on stream start.
    
    func pausePlayback() {
        Task {
            await client?.pausePlayback()
        }
    }
    
    func resumePlayback() {
        Task {
            await client?.resumePlayback()
        }
    }
    
    func stopPlayback() {
        // Pause the local engine but KEEP the Sendspin connection alive. Calling
        // disconnect() here made the player go "unavailable" on the server after every
        // stop/track-change (and playTrack calls this before each new track), forcing a
        // manual reconnect with no audio. Staying connected keeps the player registered
        // so the next stream plays immediately; the server ends the stream on its side.
        Task {
            await client?.pausePlayback()
        }
    }
    
    func getPlaybackTime() async -> TimeInterval {
        return client?.getPlaybackTime() ?? 0
    }
}
