import Foundation
import Combine

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(String)
}

@MainActor
class XonoraClient: NSObject, ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var players: [MAPlayer] = []
    @Published var currentPlayer: MAPlayer?
    @Published var hiddenPlayerIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenPlayerIds") ?? [])
    @Published var requiresAuth: Bool = false
    @Published var serverInfo: ServerInfo?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var serverURL: URL?
    private var pendingCallbacks: [String: (Result<Data, Error>) -> Void] = [:]
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var accessToken: String?
    private var username: String?
    private var password: String?
    private var usePasswordAuth: Bool = false
    private let authMessageId = "auth-handshake"
    private let hiddenPlayerIdsKey = "hiddenPlayerIds"
    private var pingTimer: Timer?
    private var connectionTimeoutTask: Task<Void, Never>?
    private let connectionTimeout: TimeInterval = 5.0

    static let shared = XonoraClient()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 86400 
        config.timeoutIntervalForResource = 604800 
        config.connectionProxyDictionary = [:]
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .init())
    }

    var baseURL: URL? {
        return serverURL
    }

    // MARK: - Connection Management

    func connect(to serverURLString: String, accessToken: String? = nil, username: String? = nil, password: String? = nil) {
        switch connectionState {
        case .connected, .connecting, .authenticating:
            return
        default:
            break
        }

        guard let url = URL(string: serverURLString) else {
            connectionState = .error(NSLocalizedString("Invalid server URL", comment: "Connection error"))
            return
        }

        self.serverURL = url
        self.accessToken = accessToken
        self.username = username
        self.password = password
        self.usePasswordAuth = accessToken?.isEmpty ?? true && username?.isEmpty == false && password?.isEmpty == false
        connectionState = .connecting
        
        var wsComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        wsComponents?.scheme = url.scheme == "https" ? "wss" : "ws"
        wsComponents?.path = "/ws"

        guard let wsURL = wsComponents?.url else {
            connectionState = .error(NSLocalizedString("Failed to create WebSocket URL", comment: "Connection error"))
            return
        }

        var request = URLRequest(url: wsURL)
        if let scheme = url.scheme, let host = url.host {
            let portString = url.port.map { ":\($0)" } ?? ""
            let origin = "\(scheme)://\(host)\(portString)"
            request.addValue(origin, forHTTPHeaderField: "Origin")
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        stopPingTimer()
        cancelConnectionTimeout()

        appLog("[XonoraClient] Connecting to \(wsURL.absoluteString)")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()
        startPingTimer()
        startConnectionTimeout()
    }

    private func startConnectionTimeout() {
        cancelConnectionTimeout()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(5.0 * 1_000_000_000))
            guard let self = self, !Task.isCancelled else { return }
            if self.connectionState == .connecting {
                self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                self.connectionState = .error(NSLocalizedString("Connection timed out.", comment: "Connection error"))
            }
        }
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
    }

    func disconnect() {
        stopReconnecting()
        stopPingTimer()
        cancelConnectionTimeout()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        serverInfo = nil
    }

    func stopReconnecting() {
        reconnectAttempts = maxReconnectAttempts
    }

    func resetReconnectionAttempts() {
        reconnectAttempts = 0
    }

    private func reconnect() {
        guard reconnectAttempts < maxReconnectAttempts, let serverURL = serverURL else {
            connectionState = .error(NSLocalizedString("Failed to reconnect.", comment: "Connection error"))
            return
        }

        reconnectAttempts += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(reconnectAttempts) * 2) { [weak self] in
            guard let self = self, self.reconnectAttempts < self.maxReconnectAttempts else { return }
            // connect() will set connectionState = .connecting itself
            if self.usePasswordAuth {
                self.connect(to: serverURL.absoluteString, accessToken: self.accessToken, username: self.username, password: self.password)
            } else {
                self.connect(to: serverURL.absoluteString, accessToken: self.accessToken)
            }
        }
    }

    // MARK: - WebSocket Communication

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPing() }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        webSocketTask?.sendPing { _ in }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handleMessage(text) }
                @unknown default: break
                }
                self.receiveMessage()
            case .failure(let error):
                Task { @MainActor in
                    appLog("[XonoraClient] WebSocket failure: \(error.localizedDescription)")
                    self.connectionState = .error(error.localizedDescription)
                    self.reconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        Task { @MainActor in
            if let messageId = json["message_id"] as? String, messageId == authMessageId {
                if let result = json["result"] as? [String: Any], let authenticated = result["authenticated"] as? Bool, authenticated {
                    appLog("[XonoraClient] Authenticated successfully")
                    connectionState = .connected
                    reconnectAttempts = 0
                    if let token = result["token"] as? String {
                        self.accessToken = token
                        KeychainHelper.shared.saveToken(token)
                        NotificationCenter.default.post(name: .tokenRefreshed, object: nil, userInfo: ["token": token])
                    }
                    await fetchPlayers()
                } else {
                    connectionState = .error(NSLocalizedString("Authentication failed.", comment: "Auth error"))
                }
                return
            }

            if let serverVersion = json["server_version"] as? String {
                cancelConnectionTimeout()
                serverInfo = ServerInfo(
                    serverVersion: serverVersion,
                    schemaVersion: json["schema_version"] as? Int ?? 0,
                    minSchemaVersion: json["min_supported_schema_version"] as? Int ?? 0,
                    serverID: json["server_id"] as? String ?? ""
                )

                if (serverInfo?.schemaVersion ?? 0) >= 28 {
                    if accessToken != nil {
                        connectionState = .authenticating
                        await authenticate()
                    } else {
                        connectionState = .error(NSLocalizedString("Authentication required.", comment: "Auth error"))
                    }
                } else {
                    connectionState = .connected
                    reconnectAttempts = 0
                    await fetchPlayers()
                }
                return
            }

            if let messageId = json["message_id"] as? String,
               let callback = pendingCallbacks.removeValue(forKey: messageId) {
                callback(.success(data))
            }

            if let event = json["event"] as? String {
                handleEvent(event, data: json)
            }

            if let errorCode = json["error_code"] as? Int, errorCode == 20 {
                requiresAuth = true
                if accessToken == nil {
                    connectionState = .error(NSLocalizedString("Authentication required.", comment: "Auth error"))
                }
            }
        }
    }

    private func authenticate() async {
        let authArgs: [String: Any]
        if usePasswordAuth, let user = username?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty,
           let pass = password?.trimmingCharacters(in: .whitespacesAndNewlines), !pass.isEmpty {
            authArgs = ["username": user, "password": pass]
        } else if let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            authArgs = ["token": token]
        } else {
            return
        }
        let authPayload: [String: Any] = [
            "message_id": authMessageId,
            "command": "auth",
            "args": authArgs
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: authPayload)
            let text = String(data: data, encoding: .utf8) ?? ""
            webSocketTask?.send(.string(text)) { _ in }
        } catch {}
    }

    private func handleEvent(_ event: String, data: [String: Any]) {
        switch event {
        case "player_updated", "players_updated":
            Task { await fetchPlayers() }
        case "queue_updated":
            if let eventData = data["data"] as? [String: Any] {
                NotificationCenter.default.post(name: .queueUpdated, object: nil, userInfo: eventData)
            }
        case "media_item_added", "media_item_updated", "media_item_deleted", "music_sync_completed":
            // The server finished (or progressed) a library sync — notify so the
            // library reloads and newly scanned files appear.
            NotificationCenter.default.post(name: .libraryUpdated, object: nil)
        default: break
        }
    }

    private func sendCommand(_ command: String, args: [String: Any] = [:]) async throws -> Data {
        guard connectionState == .connected else {
            throw NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Not connected", comment: "Connection error")])
        }
        let messageId = UUID().uuidString
        let payload: [String: Any] = ["message_id": messageId, "command": command, "args": args]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""

        return try await withCheckedThrowingContinuation { continuation in
            pendingCallbacks[messageId] = { result in
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            webSocketTask?.send(.string(text)) { error in
                if let error = error {
                    self.pendingCallbacks.removeValue(forKey: messageId)
                    continuation.resume(throwing: error)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                if let callback = self?.pendingCallbacks.removeValue(forKey: messageId) {
                    callback(.failure(NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Timeout", comment: "Connection error")])))
                }
            }
        }
    }

    // MARK: - API Methods

    func fetchPlayers() async {
        do {
            let data = try await sendCommand("players/all")
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [[String: Any]] {
                let playersData = try JSONSerialization.data(withJSONObject: result)
                let decoder = JSONDecoder()
                self.players = (try? decoder.decode([MAPlayer].self, from: playersData)) ?? []

                if let current = currentPlayer {
                    if let updated = players.first(where: { $0.playerId == current.playerId }) {
                        if updated.available { currentPlayer = updated } else { currentPlayer = nil }
                    } else { currentPlayer = nil }
                }

                // Prefer THIS device's own player (matched by our stable universal
                // player id) when it is available, so commands and resume always
                // target the right player even when stale duplicates linger.
                let myId = SendspinClient.shared.universalPlayerId
                if let mine = players.first(where: { $0.playerId == myId && $0.available && !hiddenPlayerIds.contains($0.playerId) }) {
                    if currentPlayer == nil || currentPlayer?.playerId != mine.playerId { currentPlayer = mine }
                } else {
                    let sendspinPlayer = players.first(where: { $0.available && !hiddenPlayerIds.contains($0.playerId) && $0.provider == "sendspin" && !$0.name.contains("Web") })
                    if let best = sendspinPlayer {
                        if currentPlayer == nil || currentPlayer?.playerId != best.playerId { currentPlayer = best }
                    } else if currentPlayer == nil, let first = players.first(where: { $0.available && !hiddenPlayerIds.contains($0.playerId) }) {
                        currentPlayer = first
                    }
                }
            }
        } catch {}
    }

    var visiblePlayers: [MAPlayer] {
        return players.filter { !hiddenPlayerIds.contains($0.playerId) }
    }

    func hidePlayer(_ playerId: String) {
        hiddenPlayerIds.insert(playerId)
        UserDefaults.standard.set(Array(hiddenPlayerIds), forKey: hiddenPlayerIdsKey)
        if currentPlayer?.playerId == playerId { currentPlayer = nil }
    }

    func unhideAllPlayers() {
        hiddenPlayerIds.removeAll()
        UserDefaults.standard.removeObject(forKey: hiddenPlayerIdsKey)
        if currentPlayer == nil, let first = players.first(where: { $0.available }) {
            currentPlayer = first
        }
    }

    private func parseLibraryResult<T: Codable>(_ data: Data) -> (items: [T], total: Int) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], 0) }
        let rawItems: [[String: Any]]
        let total: Int
        if let resultDict = json["result"] as? [String: Any] {
            rawItems = (resultDict["items"] as? [[String: Any]]) ?? []
            total = resultDict["total"] as? Int ?? rawItems.count
        } else if let resultArray = json["result"] as? [[String: Any]] {
            rawItems = resultArray
            total = rawItems.count
        } else {
            return ([], 0)
        }
        let decoded: [T] = (try? JSONSerialization.data(withJSONObject: rawItems)).flatMap { try? JSONDecoder().decode([T].self, from: $0) } ?? []
        return (decoded, total)
    }

    func fetchAlbums(offset: Int = 0, limit: Int = 500) async throws -> (items: [Album], total: Int) {
        var args: [String: Any] = ["offset": offset, "limit": limit]
        let data = try await sendCommand("music/albums/library_items", args: args)
        return parseLibraryResult(data)
    }

    func fetchPlaylists(offset: Int = 0, limit: Int = 500) async throws -> (items: [Playlist], total: Int) {
        var args: [String: Any] = ["offset": offset, "limit": limit]
        let data = try await sendCommand("music/playlists/library_items", args: args)
        return parseLibraryResult(data)
    }

    func fetchArtists(offset: Int = 0, limit: Int = 500) async throws -> (items: [Artist], total: Int) {
        var args: [String: Any] = ["offset": offset, "limit": limit]
        let data = try await sendCommand("music/artists/library_items", args: args)
        return parseLibraryResult(data)
    }

    func fetchTracks(offset: Int = 0, limit: Int = 500) async throws -> (items: [Track], total: Int) {
        var args: [String: Any] = ["offset": offset, "limit": limit]
        let data = try await sendCommand("music/tracks/library_items", args: args)
        return parseLibraryResult(data)
    }

    func fetchAlbumTracks(albumId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/albums/album_tracks", args: ["item_id": albumId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Track].self, from: resultData)) ?? []
    }

    func fetchPlaylistTracks(playlistId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/playlists/playlist_tracks", args: ["item_id": playlistId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Track].self, from: resultData)) ?? []
    }

    func fetchArtistAlbums(artistId: String, provider: String) async throws -> [Album] {
        let data = try await sendCommand("music/artists/artist_albums", args: ["item_id": artistId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Album].self, from: resultData)) ?? []
    }

    func fetchArtistTracks(artistId: String, provider: String) async throws -> [Track] {
        let data = try await sendCommand("music/artists/artist_tracks", args: ["item_id": artistId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Track].self, from: resultData)) ?? []
    }

    func search(query: String) async throws -> (albums: [Album], artists: [Artist], tracks: [Track]) {
        let data = try await sendCommand("music/search", args: ["search_query": query, "media_types": ["album", "artist", "track"], "limit": 20])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [String: Any] else { return ([], [], []) }
        let decoder = JSONDecoder()
        var albums: [Album] = []
        var artists: [Artist] = []
        var tracks: [Track] = []

        if let albumsArray = result["albums"] as? [[String: Any]] {
            let albumsData = try JSONSerialization.data(withJSONObject: albumsArray)
            albums = (try? decoder.decode([Album].self, from: albumsData)) ?? []
        }
        if let artistsArray = result["artists"] as? [[String: Any]] {
            let artistsData = try JSONSerialization.data(withJSONObject: artistsArray)
            artists = (try? decoder.decode([Artist].self, from: artistsData)) ?? []
        }
        if let tracksArray = result["tracks"] as? [[String: Any]] {
            let tracksData = try JSONSerialization.data(withJSONObject: tracksArray)
            tracks = (try? decoder.decode([Track].self, from: tracksData)) ?? []
        }
        return (albums, artists, tracks)
    }

    func deleteQueueItem(at index: Int) async {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try? await sendCommand("player_queues/delete_item", args: [
            "queue_id": playerId,
            "item_id_or_index": index
        ])
    }

    struct ActiveQueueSnapshot {
        let tracks: [Track]
        let currentIndex: Int
        let elapsed: TimeInterval
        let state: String?
        let currentTrack: Track?
    }

    /// Fetch the server's active queue (current track, position, state and the full
    /// item list) so the app can restore the Now Playing screen after a cold launch.
    func fetchActiveQueue() async -> ActiveQueueSnapshot? {
        guard let playerId = currentPlayer?.playerId else { return nil }
        // NOTE: get_active_queue takes `player_id` (NOT `queue_id`); passing queue_id
        // silently returns nothing.
        guard let data = try? await sendCommand("player_queues/get_active_queue", args: ["player_id": playerId]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else { return nil }

        let state = result["state"] as? String
        let currentIndex = result["current_index"] as? Int ?? 0
        let elapsed: TimeInterval = (result["elapsed_time"] as? Double)
            ?? (result["elapsed_time"] as? Int).map { TimeInterval($0) } ?? 0

        func decodeTrack(_ container: [String: Any]?) -> Track? {
            // Queue items carry the full track only inside `media_item`.
            guard let mi = container?["media_item"] as? [String: Any],
                  let d = try? JSONSerialization.data(withJSONObject: mi) else { return nil }
            return try? JSONDecoder().decode(Track.self, from: d)
        }

        let currentTrack = decodeTrack(result["current_item"] as? [String: Any])

        var tracks: [Track] = []
        if let itemsData = try? await sendCommand("player_queues/items", args: ["queue_id": playerId, "limit": 500]),
           let itemsJson = try? JSONSerialization.jsonObject(with: itemsData) as? [String: Any],
           let items = itemsJson["result"] as? [[String: Any]] {
            tracks = items.compactMap { decodeTrack($0) }
        }

        return ActiveQueueSnapshot(tracks: tracks, currentIndex: currentIndex, elapsed: elapsed, state: state, currentTrack: currentTrack)
    }

    func fetchQueueItems() async -> [QueueItem] {
        guard let playerId = currentPlayer?.playerId else { return [] }
        guard let data = try? await sendCommand("player_queues/items", args: ["queue_id": playerId]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]],
              let resultData = try? JSONSerialization.data(withJSONObject: result) else { return [] }
        return (try? JSONDecoder().decode([QueueItem].self, from: resultData)) ?? []
    }

    /// Move a queue item identified by its URI by a relative position shift.
    /// Resolves the server-side queue_item_id via URI match to stay robust against index drift.
    func moveQueueItem(matchingURI uri: String, posShift: Int, fallbackName: String? = nil) async {
        guard posShift != 0, let playerId = currentPlayer?.playerId else { return }
        let items = await fetchQueueItems()
        let item = items.first(where: { $0.uri == uri })
            ?? fallbackName.flatMap { name in items.first(where: { $0.name == name }) }
        guard let item = item else {
            print("[XonoraClient] moveQueueItem: no matching queue item for \(uri)")
            return
        }
        _ = try? await sendCommand("player_queues/move_item", args: [
            "queue_id": playerId,
            "queue_item_id": item.queueItemId,
            "pos_shift": posShift
        ])
    }

    /// Trigger a full server-side rescan of all music providers so files newly
    /// added to the server's music folders get indexed into the library.
    /// Runs in the background on the server; results arrive via media_item_added /
    /// music_sync_completed events.
    func syncLibrary() async {
        _ = try? await sendCommand("music/sync")
    }

    func addToLibrary(itemId: String, provider: String) async throws {
        let trackUri = "\(provider)://track/\(itemId)"
        _ = try await sendCommand("music/library/add_item", args: ["item": trackUri])
    }

    func playMedia(uris: [String], queueOption: String = "replace") async throws {
        guard let player = currentPlayer else { throw NSError(domain: "MusicAssistant", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("No player", comment: "Playback error")]) }
        _ = try await sendCommand("player_queues/play_media", args: ["queue_id": player.playerId, "media": uris, "option": queueOption])
    }

    func playPause() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/play_pause", args: ["queue_id": playerId])
    }

    func play() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("players/cmd/play", args: ["player_id": playerId])
    }

    func pause() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("players/cmd/pause", args: ["player_id": playerId])
    }

    func next() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/next", args: ["queue_id": playerId])
    }

    func previous() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/previous", args: ["queue_id": playerId])
    }

    func stopQueue() async {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try? await sendCommand("player_queues/stop", args: ["queue_id": playerId])
    }

    func stop() async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/stop", args: ["queue_id": playerId])
    }

    func seek(position: TimeInterval) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/seek", args: ["queue_id": playerId, "position": Int(position)])
    }

    func switchPlayer(playerId: String) async {
        if let player = players.first(where: { $0.playerId == playerId }) {
            currentPlayer = player
        }
    }

    func renamePlayer(playerId: String, name: String) async {
        // MA stores the custom player name as a root-level "name" key in PlayerConfig
        // (handled by Config.update). "name_override" is not a recognized key and is ignored.
        _ = try? await sendCommand("config/players/save", args: [
            "player_id": playerId,
            "values": ["name": name]
        ])
        await fetchPlayers()
    }

    /// Permanently remove a player config from the server (真正删除，而非本地隐藏).
    /// Works for offline / removable players; for providers that re-announce their
    /// players we also hide locally so it disappears immediately and stays gone.
    func removePlayer(_ playerId: String) async {
        _ = try? await sendCommand("config/players/remove", args: ["player_id": playerId])
        if currentPlayer?.playerId == playerId { currentPlayer = nil }
        await fetchPlayers()
        // Only fall back to a local hide if the server still reports the player
        // (i.e. a provider re-announced it). Offline devices are truly removed, so
        // no "Show Hidden Players" entry appears for the normal delete case.
        if players.contains(where: { $0.playerId == playerId }) {
            hidePlayer(playerId)
        }
    }

    func setVolume(_ volume: Int) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("players/cmd/volume_set", args: ["player_id": playerId, "volume_level": volume])
    }

    func toggleMute() async {
        guard let player = currentPlayer else { return }
        let newMuted = !(player.volumeMuted ?? false)
        _ = try? await sendCommand("players/cmd/volume_mute", args: ["player_id": player.playerId, "muted": newMuted])
        await fetchPlayers()
    }

    func setShuffle(enabled: Bool) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/shuffle", args: ["queue_id": playerId, "shuffle_enabled": enabled])
    }

    func setRepeat(mode: String) async throws {
        guard let playerId = currentPlayer?.playerId else { return }
        _ = try await sendCommand("player_queues/repeat", args: ["queue_id": playerId, "repeat_mode": mode])
    }

    func toggleItemFavorite(uri: String, favorite: Bool) async throws {
        let command = favorite ? "music/favorites/add_item" : "music/favorites/remove_item"
        _ = try await sendCommand(command, args: ["item": uri])
    }

    struct PlayableMediaItem {
        let name: String
        let subtitle: String
        let uri: String
    }

    private func parsePlayableItems(_ data: Data) -> [PlayableMediaItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else { return [] }
        return result.compactMap { item -> PlayableMediaItem? in
            guard let name = item["name"] as? String, let uri = item["uri"] as? String else { return nil }
            let artists = item["artists"] as? [[String: Any]]
            let artistName = artists?.first?["name"] as? String
            let albumName = (item["album"] as? [String: Any])?["name"] as? String
            let subtitle = artistName ?? albumName ?? (item["media_type"] as? String ?? "")
            return PlayableMediaItem(name: name, subtitle: subtitle, uri: uri)
        }
    }

    func fetchRecentlyPlayed(limit: Int = 15) async throws -> [PlayableMediaItem] {
        let data = try await sendCommand("music/recently_played_items", args: ["limit": limit])
        return parsePlayableItems(data)
    }

    func fetchInProgress(limit: Int = 10) async throws -> [PlayableMediaItem] {
        let data = try await sendCommand("music/in_progress_items", args: ["limit": limit])
        return parsePlayableItems(data)
    }

    func fetchRecommendations(limit: Int = 15) async throws -> [PlayableMediaItem] {
        let data = try await sendCommand("music/recommendations", args: ["limit": limit])
        return parsePlayableItems(data)
    }

    func fetchPodcasts(offset: Int = 0, limit: Int = 500) async throws -> (items: [Podcast], total: Int) {
        let data = try await sendCommand("music/podcasts/library_items", args: ["offset": offset, "limit": limit])
        return parseLibraryResult(data)
    }

    func fetchPodcastEpisodes(podcastId: String, provider: String) async throws -> [Episode] {
        let data = try await sendCommand("music/podcasts/podcast_episodes", args: ["item_id": podcastId, "provider_instance_id_or_domain": provider])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let result = json["result"] as? [[String: Any]] else { return [] }
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return (try? JSONDecoder().decode([Episode].self, from: resultData)) ?? []
    }

    func fetchRadioStations(offset: Int = 0, limit: Int = 500) async throws -> (items: [RadioStation], total: Int) {
        let data = try await sendCommand("music/radios/library_items", args: ["offset": offset, "limit": limit])
        return parseLibraryResult(data)
    }

    func fetchLyrics(track: Track) async throws -> LyricsResponse {
        var trackDict: [String: Any] = [
            "item_id": track.itemId,
            "provider": track.provider,
            "name": track.name,
            "uri": track.uri,
            "media_type": "track"
        ]
        // Include provider mappings so the server can resolve where to fetch lyrics from.
        if let mappings = track.providerMappings, !mappings.isEmpty {
            trackDict["provider_mappings"] = mappings.map { [
                "item_id": $0.itemId,
                "provider_domain": $0.providerDomain,
                "provider_instance": $0.providerInstance
            ] }
        }
        let data = try await sendCommand("metadata/get_track_lyrics", args: ["track": trackDict])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LyricsResponse(lyrics: nil, hasSynced: false)
        }
        // get_track_lyrics returns a tuple (lyrics, lrc_lyrics) -> JSON array of up to
        // two nullable strings. Prefer the synced LRC form when present.
        let result = json["result"] as? [Any]
        let plain = (result?.count ?? 0) > 0 ? result?[0] as? String : nil
        let lrc = (result?.count ?? 0) > 1 ? result?[1] as? String : nil

        if let lrc = lrc, !lrc.isEmpty {
            let parsed = parseLRC(lrc)
            if !parsed.isEmpty { return LyricsResponse(lyrics: parsed, hasSynced: true) }
        }
        if let plain = plain, !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines).enumerated().map { idx, line in
                Lyric(lineId: "\(idx)", start: nil, end: nil, text: line)
            }
            return LyricsResponse(lyrics: lines, hasSynced: false)
        }
        return LyricsResponse(lyrics: nil, hasSynced: false)
    }

    /// Parse LRC-format synced lyrics ("[mm:ss.xx] text") into timed Lyric lines.
    private func parseLRC(_ lrc: String) -> [Lyric] {
        let pattern = "\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var parsed: [(start: TimeInterval, text: String)] = []
        for line in lrc.components(separatedBy: .newlines) {
            let nsline = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsline.length))
            guard let last = matches.last else { continue }
            let textStart = last.range.location + last.range.length
            let text = nsline.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let mins = Double(nsline.substring(with: m.range(at: 1))) ?? 0
                let secs = Double(nsline.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = nsline.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10.0, Double(f.count))
                }
                parsed.append((mins * 60 + secs + frac, text))
            }
        }
        parsed.sort { $0.start < $1.start }
        return parsed.enumerated().map { i, line in
            let end = i + 1 < parsed.count ? parsed[i + 1].start : nil
            return Lyric(lineId: "\(i)", start: line.start, end: end, text: line.text)
        }
    }

    // MA schema >= 31 enforces an imageproxy size whitelist ([80,160,256,512,1024]);
    // any other size returns HTTP 400 and the image fails to load. These values are
    // also valid on older servers (which accept arbitrary sizes), so they work
    // universally without needing a schema check.
    enum ImageSize: Int {
        case thumbnail = 160
        case small = 256
        case medium = 512
        case large = 1024
    }

    func getImageURL(for urlString: String?, size: ImageSize = .medium) -> URL? {
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else { return nil }
        if urlString.hasPrefix("data:image") { return URL(string: urlString) }
        if urlString.contains("mzstatic.com") { return optimizeImageURL(urlString, size: size) }
        if let baseURL = serverURL, urlString.contains(baseURL.host ?? ""), (urlString.contains("/imageproxy") || urlString.contains("/api/imageproxy")) { return URL(string: urlString) }
        if urlString.hasPrefix("http") && !urlString.contains("localhost") && !urlString.contains("127.0.0.1") { return URL(string: urlString) }
        guard let baseURL = serverURL else { return nil }

        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        let baseParams = baseURL.path.trimmingCharacters(in: .init(charactersIn: "/"))

        // proxy_id format: short alphanumeric string with no slashes or colons
        // Use the new canonical /imageproxy/{proxy_id} endpoint
        if !urlString.contains("/") && !urlString.contains(":") {
            components.path = baseParams.isEmpty ? "/imageproxy/\(urlString)" : "/\(baseParams)/imageproxy/\(urlString)"
            components.queryItems = [URLQueryItem(name: "size", value: "\(size.rawValue)")]
        } else {
            components.path = baseParams.isEmpty ? "/imageproxy" : "/\(baseParams)/imageproxy"
            components.queryItems = [URLQueryItem(name: "path", value: urlString), URLQueryItem(name: "size", value: "\(size.rawValue)")]
        }
        if let token = accessToken { components.queryItems?.append(URLQueryItem(name: "token", value: token)) }
        return components.url
    }

    private func optimizeImageURL(_ urlString: String, size: ImageSize) -> URL? {
        var optimizedString = urlString
        if urlString.contains("mzstatic.com") {
            let pattern = "\\d+x\\d+bb"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(urlString.startIndex..., in: urlString)
                optimizedString = regex.stringByReplacingMatches(in: urlString, options: [], range: range, withTemplate: "\(size.rawValue)x\(size.rawValue)bb")
            }
        }
        return URL(string: optimizedString)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        let criticalKeywords = ["Connecting", "Error", "Handshake", "authenticated", "timeout", "command: player_queues/play_media"]
        if criticalKeywords.contains(where: { message.contains($0) }) {
            let logMessage = message.count > 1000 ? String(message.prefix(1000)) + "... (truncated)" : message
            print("[MusicAssistant] \(logMessage)")
        }
        #endif
    }
}

struct ServerInfo {
    let serverVersion: String
    let schemaVersion: Int
    let minSchemaVersion: Int
    let serverID: String
}

extension Notification.Name {
    static let queueUpdated = Notification.Name("queueUpdated")
    static let tokenRefreshed = Notification.Name("tokenRefreshed")
    static let libraryUpdated = Notification.Name("libraryUpdated")
}

// MARK: - In-app diagnostics log

struct AppLogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let message: String
}

/// Captures the diagnostic log lines that previously only went to the Xcode
/// console, so they can be viewed on-device from Settings → Logs. Backed by a
/// bounded ring buffer. Mutations are funneled onto the main queue so it is safe
/// to call `log(_:)` from any thread.
final class AppLogger: ObservableObject {
    static let shared = AppLogger()
    @Published private(set) var entries: [AppLogEntry] = []
    private let maxEntries = 2000

    private init() {}

    func log(_ message: String) {
        let truncated = message.count > 2000 ? String(message.prefix(2000)) + "…" : message
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.entries.append(AppLogEntry(date: Date(), message: truncated))
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }

    func exportText() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { "[\(fmt.string(from: $0.date))] \($0.message)" }.joined(separator: "\n")
    }
}

/// Global helper used across the app so important events surface both in the
/// Xcode console and in the in-app log viewer.
func appLog(_ message: String) {
    print(message)
    AppLogger.shared.log(message)
}
