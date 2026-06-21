import Foundation
import Combine
import SendspinKit

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var isNowPlayingPresented = false
    @Published var serverURL: String = ""
    @Published var accessToken: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isAuthenticating = false
    @Published var connectionError: String?
    @Published var showingServerSetup = false
    @Published var requiresAuth = false
    @Published var playbackError: String?
    @Published var sendspinEnabled: Bool = false
    @Published var sendspinConnected: Bool = false
    @Published var currentTrack: Track?
    @Published var currentSource: String?
    @Published var discoveredServers: [DiscoveredServer] = []

    private let client = XonoraClient.shared
    private let sendspinClient = SendspinClient.shared
    private let discovery = ServerDiscovery()
    let playerManager = PlayerManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var discoveryTask: Task<Void, Never>?

    private let serverURLKey = "MusicAssistantServerURL"
    private let accessTokenKey = "MusicAssistantAccessToken"
    private let sendspinEnabledKey = "MusicAssistantSendspinEnabled"

    init() {
        loadSavedCredentials()
        setupBindings()
    }

    private func setupBindings() {
        // Listen for Playback Errors
        playerManager.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .error(let message) = state {
                    self?.playbackError = message
                }
            }
            .store(in: &cancellables)

        client.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .connected:
                    self.isConnected = true
                    self.isConnecting = false
                    self.isAuthenticating = false
                    self.connectionError = nil
                    // Restore the Now Playing screen from the server's active queue
                    // (e.g. after a force-quit relaunch where local state was lost).
                    Task { await PlayerManager.shared.restoreFromServer() }
                case .connecting:
                    self.isConnecting = true
                    self.isAuthenticating = false
                    self.connectionError = nil
                case .authenticating:
                    self.isConnecting = false
                    self.isAuthenticating = true
                    self.connectionError = nil
                case .disconnected:
                    self.isConnected = false
                    self.isConnecting = false
                    self.isAuthenticating = false
                case .error(let message):
                    self.isConnected = false
                    self.isConnecting = false
                    self.isAuthenticating = false
                    self.connectionError = message
                }
            }
            .store(in: &cancellables)

        client.$requiresAuth
            .receive(on: DispatchQueue.main)
            .assign(to: &$requiresAuth)

        // Sendspin connection state
        sendspinClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$sendspinConnected)
            
        // Sync current track
        playerManager.$currentTrack
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTrack)
            
        // Sync current source
        playerManager.$currentSource
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentSource)
    }

    func startDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = Task {
            await discovery.startDiscovery()
            for await servers in await discovery.servers {
                self.discoveredServers = servers
            }
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        Task {
            await discovery.stopDiscovery()
            self.discoveredServers = []
        }
    }

    private func loadSavedCredentials() {
        if let savedURL = KeychainHelper.shared.getServerURL() ?? UserDefaults.standard.string(forKey: serverURLKey) {
            serverURL = savedURL
        }
        if let savedToken = KeychainHelper.shared.getToken() ?? UserDefaults.standard.string(forKey: accessTokenKey) {
            accessToken = savedToken
        }
        if let savedUsername = KeychainHelper.shared.getUsername() {
            username = savedUsername
        }
        
        if UserDefaults.standard.object(forKey: sendspinEnabledKey) == nil {
            sendspinEnabled = true
            UserDefaults.standard.set(true, forKey: sendspinEnabledKey)
        } else {
            sendspinEnabled = UserDefaults.standard.bool(forKey: sendspinEnabledKey)
        }
    }

    func connectToServer() {
        guard !serverURL.isEmpty else {
            showingServerSetup = true
            return
        }

        if isConnected || isConnecting || isAuthenticating {
            return
        }

        let url = normalizeServerURL(serverURL)
        KeychainHelper.shared.saveServerURL(url)
        serverURL = url

        client.resetReconnectionAttempts()
        if !accessToken.isEmpty {
            KeychainHelper.shared.saveToken(accessToken)
            client.connect(to: url, accessToken: accessToken)
        } else if !username.isEmpty, !password.isEmpty {
            KeychainHelper.shared.saveUsername(username)
            client.connect(to: url, username: username, password: password)
        } else {
            client.connect(to: url, accessToken: nil)
        }

        if sendspinEnabled {
            connectSendspin()
        }
    }

    // MARK: - Sendspin

    func toggleSendspin(_ enabled: Bool) {
        sendspinEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: sendspinEnabledKey)

        if enabled {
            connectSendspin()
        } else {
            sendspinClient.disconnect()
        }
    }

    func connectSendspin() {
        guard !serverURL.isEmpty else { return }

        if let url = URL(string: serverURL), let host = url.host {
            let port = url.port ?? (url.scheme == "https" ? 443 : 80)
            let scheme = url.scheme == "https" ? "wss" : "ws"
            sendspinClient.connect(to: host, port: UInt16(port), scheme: scheme, accessToken: self.accessToken)
        }
    }

    func disconnect() {
        client.disconnect()
        sendspinClient.disconnect()
    }

    /// Stop all connection attempts and allow changing settings
    func stopAndShowSettings() {
        client.disconnect()
        sendspinClient.disconnect()
        showingServerSetup = true
    }

    func updateServerURL(_ url: String) {
        serverURL = normalizeServerURL(url)
        UserDefaults.standard.set(serverURL, forKey: serverURLKey)
    }

    func updateCredentials(accessToken: String) {
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessToken = trimmedToken
        if !trimmedToken.isEmpty {
            KeychainHelper.shared.saveToken(trimmedToken)
        }
    }

    func updateUsernamePassword(username: String, password: String) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        self.accessToken = ""
        KeychainHelper.shared.saveUsername(self.username)
        KeychainHelper.shared.deleteToken()
    }

    private func normalizeServerURL(_ url: String) -> String {
        var normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add http:// if no scheme provided
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            normalizedURL = "http://\(normalizedURL)"
        }

        // Remove trailing slash
        if normalizedURL.hasSuffix("/") {
            normalizedURL = String(normalizedURL.dropLast())
        }

        return normalizedURL
    }

    // MARK: - Playback Control

    func playTrack(_ track: Track, fromQueue tracks: [Track]? = nil, sourceName: String? = nil, shuffle: Bool = false) {
        playerManager.playTrack(track, fromQueue: tracks, sourceName: sourceName, shuffle: shuffle)
    }

    func playAlbum(_ tracks: [Track], startingAt index: Int = 0, shuffle: Bool = false) {
        playerManager.playAlbum(tracks, startingAt: index, shuffle: shuffle)
    }

    func togglePlayPause() {
        playerManager.togglePlayPause()
    }

    func next() {
        playerManager.next()
    }

    func previous() {
        playerManager.previous()
    }

    func seek(to time: TimeInterval) {
        playerManager.seek(to: time)
    }

    func toggleShuffle() {
        playerManager.toggleShuffle()
    }

    func cycleRepeatMode() {
        playerManager.cycleRepeatMode()
    }

    // MARK: - Helper Properties

    var isPlaying: Bool {
        playerManager.isPlaying
    }

    var hasTrack: Bool {
        playerManager.currentTrack != nil
    }

    var progress: Double {
        playerManager.progress
    }

    var currentTime: TimeInterval {
        playerManager.currentTime
    }

    var duration: TimeInterval {
        playerManager.duration
    }

    var shuffleEnabled: Bool {
        playerManager.shuffleEnabled
    }

    var repeatMode: RepeatMode {
        playerManager.repeatMode
    }

    func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}