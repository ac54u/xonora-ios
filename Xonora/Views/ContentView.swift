import SwiftUI
import UIKit
import FluidGradient

struct ContentView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @State private var selectedTab = 0
    @State private var isPlayerExpanded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "rectangle.stack.fill")
                    }
                    .tag(0)

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(1)

                NowPlayingView(isPresentedModally: false)
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(3)
            }

            // Mini Player Overlay - positioned above system tab bar.
            // Hidden on the Now Playing tab (2) and Settings tab (3) so it doesn't
            // overlap the full player controls.
            if playerViewModel.hasTrack && !isPlayerExpanded && selectedTab != 2 && selectedTab != 3 {
                MiniPlayerView {
                    withAnimation {
                        isPlayerExpanded = true
                    }
                }
                .padding(.bottom, 52) // Height of standard tab bar + margin
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .sheet(isPresented: $playerViewModel.showingServerSetup) {
            ServerSetupView()
        }
        .fullScreenCover(isPresented: $isPlayerExpanded) {
            NowPlayingView(isPresentedModally: true)
        }
        .onAppear {
            if playerViewModel.serverURL.isEmpty {
                playerViewModel.showingServerSetup = true
            } else {
                playerViewModel.connectToServer()
            }
        }
        .alert("Playback Error", isPresented: Binding(
            get: { playerViewModel.playbackError != nil },
            set: { _ in playerViewModel.playbackError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = playerViewModel.playbackError {
                Text(error)
            }
        }
    }
}

struct ServerSetupView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @State private var serverURL: String = ""
    @State private var accessToken: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var authMethod: AuthMethod = .token

    @Environment(\.dismiss) private var dismiss

    enum AuthMethod: String, CaseIterable {
        case token = "Token"
        case password = "Username/Password"

        var localizedName: String {
            NSLocalizedString(self.rawValue, comment: "Auth method")
        }
    }

    var body: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    if !playerViewModel.serverURL.isEmpty {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)
                    }

                    headerView
                        .padding(.top, playerViewModel.serverURL.isEmpty ? 60 : 20)

                    VStack(spacing: 20) {
                        serverURLField
                        authMethodPicker
                        if authMethod == .token {
                            accessTokenField
                        } else {
                            usernameField
                            passwordField
                        }
                    }
                    .padding(24)
                    .background(Color(UIColor.systemBackground).opacity(0.2).background(.thinMaterial))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 24)

                    if !playerViewModel.discoveredServers.isEmpty {
                        discoveredServersSection
                            .padding(.horizontal, 24)
                    }

                    statusView
                        .padding(.horizontal, 24)

                    Spacer(minLength: 40)

                    connectButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }

            if !playerViewModel.serverURL.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding()
                        }
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            serverURL = playerViewModel.serverURL
            accessToken = playerViewModel.accessToken
            username = playerViewModel.username
            if !playerViewModel.accessToken.isEmpty {
                authMethod = .token
            } else if !playerViewModel.username.isEmpty {
                authMethod = .password
            }
            playerViewModel.startDiscovery()
        }
        .onDisappear {
            playerViewModel.stopDiscovery()
        }
        .onChange(of: playerViewModel.isConnected) { connected in
            if connected {
                dismiss()
            }
        }
    }

    // MARK: - Discovered Servers

    private var discoveredServersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered Servers")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .padding(.leading, 4)

            ForEach(playerViewModel.discoveredServers) { server in
                Button {
                    // Normalize the URL from discovery
                    // Discovered server URL is ws:// but we want http:// for the main API
                    let host = server.hostname
                    let port = server.port
                    serverURL = "http://\(host):\(port)"
                    
                    // If the discovery URL has a different port or path, it's handled by sendspinClient.connect
                    // But for the main MA server, we usually expect standard ports.
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                            Text(server.url.absoluteString)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.xonoraCyan)
                    }
                    .padding()
                    .background(glassBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        FluidGradient(
            blobs: [.pink, .cyan, .purple, .pink],
            highlights: [.pink, .cyan, .purple],
            speed: 0.5,
            blur: 0.95
        )
        .background(.quaternary)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hifispeaker.2.fill")
                .font(.largeTitle.weight(.medium))
                .foregroundStyle(Color.xonoraGradient)

            VStack(spacing: 8) {
                Text("Xonora")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.white)

                Text("Connect to Music Assistant")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Server URL Field

    private var serverURLField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Server Address", systemImage: "server.rack")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                TextField("", text: $serverURL, prompt: Text("http://192.168.1.100:8095").foregroundColor(.secondary.opacity(0.5)))
                    .foregroundColor(.primary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            .padding()
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            Text("Your Music Assistant server URL with port")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Auth Method Picker

    private var authMethodPicker: some View {
        Picker("Auth Method", selection: $authMethod) {
            ForEach(AuthMethod.allCases, id: \.self) { method in
                Text(method.localizedName).tag(method)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Access Token Field

    private var accessTokenField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Access Token", systemImage: "key.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                Group {
                    if showPassword {
                        TextField("", text: $accessToken, prompt: Text("Paste your token here").foregroundColor(.secondary.opacity(0.5)))
                    } else {
                        SecureField("", text: $accessToken, prompt: Text("Paste your token here").foregroundColor(.secondary.opacity(0.5)))
                    }
                }
                .foregroundColor(.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            Text("Create a token in Music Assistant → Settings → Users")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Username Field

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Username", systemImage: "person.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                Image(systemName: "person")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                TextField("", text: $username, prompt: Text("Music Assistant username").foregroundColor(.secondary.opacity(0.5)))
                    .foregroundColor(.primary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding()
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Password Field

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Password", systemImage: "lock.shield.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                Group {
                    if showPassword {
                        TextField("", text: $password, prompt: Text("Music Assistant password").foregroundColor(.secondary.opacity(0.5)))
                    } else {
                        SecureField("", text: $password, prompt: Text("Music Assistant password").foregroundColor(.secondary.opacity(0.5)))
                    }
                }
                .foregroundColor(.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            Text("Use your Music Assistant login credentials")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        if playerViewModel.isConnecting || playerViewModel.isAuthenticating {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text(playerViewModel.isAuthenticating ? LocalizedStringKey("Authenticating...") : LocalizedStringKey("Connecting..."))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if let error = playerViewModel.connectionError {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.red.opacity(0.4), lineWidth: 1)
            )
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            playerViewModel.updateServerURL(serverURL)
            if authMethod == .token {
                playerViewModel.updateCredentials(accessToken: accessToken)
            } else {
                playerViewModel.updateUsernamePassword(username: username, password: password)
            }
            playerViewModel.connectToServer()
        } label: {
            HStack(spacing: 10) {
                if playerViewModel.isConnecting || playerViewModel.isAuthenticating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                }
                Text(buttonText)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if isButtonDisabled {
                        Color.gray.opacity(0.3)
                    } else {
                        LinearGradient(
                            colors: [Color.xonoraPurple, Color.xonoraCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: isButtonDisabled ? .clear : Color.xonoraPurple.opacity(0.5), radius: 20, y: 10)
        }
        .disabled(isButtonDisabled)
        .scaleEffect(isButtonDisabled ? 1.0 : (playerViewModel.isConnecting ? 0.98 : 1.0))
        .animation(.spring(response: 0.3), value: playerViewModel.isConnecting)
    }

    // MARK: - Helpers

    private var glassBackground: some View {
        Color.white.opacity(0.1)
            .background(.ultraThinMaterial.opacity(0.5))
    }

    private var isButtonDisabled: Bool {
        serverURL.isEmpty || playerViewModel.isConnecting || playerViewModel.isAuthenticating
    }

    private var buttonText: LocalizedStringKey {
        if playerViewModel.isAuthenticating {
            return "Authenticating"
        } else if playerViewModel.isConnecting {
            return "Connecting"
        } else {
            return "Connect"
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @EnvironmentObject var playerViewModel: PlayerViewModel

    var body: some View {
        NavigationStack {
            VStack {
                if libraryViewModel.searchQuery.isEmpty {
                    ContentUnavailableView(
                        "Search Music",
                        systemImage: "magnifyingglass",
                        description: Text("Search for albums, artists, and tracks")
                    )
                } else if libraryViewModel.isSearching {
                    ProgressView()
                } else if libraryViewModel.searchResults.albums.isEmpty &&
                          libraryViewModel.searchResults.artists.isEmpty &&
                          libraryViewModel.searchResults.tracks.isEmpty {
                    ContentUnavailableView.search(text: libraryViewModel.searchQuery)
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $libraryViewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Albums, Artists, Songs"))
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var searchResultsList: some View {
        List {
            if !libraryViewModel.searchResults.tracks.isEmpty {
                    Section(String(localized: "Songs")) {
                    ForEach(libraryViewModel.searchResults.tracks) { track in
                        TrackRow(
                            track: track,
                            showArtwork: true,
                            isPlaying: playerViewModel.playerManager.currentTrack?.id == track.id,
                            onTap: {
                                playerViewModel.playTrack(track, fromQueue: libraryViewModel.searchResults.tracks, sourceName: "Search")
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { try? await XonoraClient.shared.addToLibrary(itemId: track.itemId, provider: track.provider) }
                            } label: {
                                Label("Add to Library", systemImage: "plus")
                            }
                            .tint(.accentColor)
                        }
                        .contextMenu {
                            Button {
                                Task { try? await XonoraClient.shared.addToLibrary(itemId: track.itemId, provider: track.provider) }
                            } label: {
                                Label("Add to Library", systemImage: "plus")
                            }
                            Button {
                                playerViewModel.playerManager.playNext(track)
                            } label: {
                                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                            }
                            Button {
                                playerViewModel.playerManager.addToQueue(track)
                            } label: {
                                Label("Add to Queue", systemImage: "music.note.list")
                            }
                        }
                    }
                }
            }

            if !libraryViewModel.searchResults.albums.isEmpty {
                Section(String(localized: "Albums")) {
                    ForEach(libraryViewModel.searchResults.albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: album.imageUrl, size: .thumbnail)) {
                                    Color.clear
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading) {
                                    Text(album.name)
                                        .lineLimit(1)
                                    Text(album.artistNames)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                Task { try? await XonoraClient.shared.addToLibrary(itemId: album.itemId, provider: album.provider) }
                            } label: {
                                Label("Add to Library", systemImage: "plus")
                            }
                        }
                    }
                }
            }

            if !libraryViewModel.searchResults.artists.isEmpty {
                Section(String(localized: "Artists")) {
                    ForEach(libraryViewModel.searchResults.artists) { artist in
                        NavigationLink(destination: ArtistDetailView(artist: artist)) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 50, height: 50)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                    }

                                Text(artist.name)
                            }
                        }
                        .contextMenu {
                            Button {
                                Task { try? await XonoraClient.shared.addToLibrary(itemId: artist.itemId, provider: artist.provider) }
                            } label: {
                                Label("Add to Library", systemImage: "plus")
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: playerViewModel.hasTrack ? 130 : 50)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var client = XonoraClient.shared
    @ObservedObject private var sendspinClient = SendspinClient.shared
    @State private var localPlayerName: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Server", systemImage: "server.rack")
                        Spacer()
                        Text(playerViewModel.serverURL)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if !playerViewModel.accessToken.isEmpty {
                        HStack {
                            Label("Token", systemImage: "key.fill")
                            Spacer()
                            Text(playerViewModel.accessToken.prefix(8) + "...")
                                .foregroundColor(.secondary)
                        }
                    } else if !playerViewModel.username.isEmpty {
                        HStack {
                            Label("User", systemImage: "person.fill")
                            Spacer()
                            Text(playerViewModel.username)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Label("Status", systemImage: playerViewModel.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Spacer()
                        Text(connectionStatusText)
                            .foregroundColor(connectionStatusColor)
                    }

                    Button {
                        // Stop any ongoing connection attempts before showing settings
                        playerViewModel.stopAndShowSettings()
                    } label: {
                        Label("Change Server", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        playerViewModel.disconnect()
                        KeychainHelper.shared.clearAll()
                        playerViewModel.accessToken = ""
                        playerViewModel.username = ""
                        playerViewModel.password = ""
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } header: {
                    Text("Connection")
                }

                Section {
                    Toggle("Enable Sendspin", isOn: Binding(
                        get: { playerViewModel.sendspinEnabled },
                        set: { playerViewModel.toggleSendspin($0) }
                    ))

                    if playerViewModel.sendspinEnabled {
                        HStack {
                            Label("Sendspin Status", systemImage: playerViewModel.sendspinConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Spacer()
                            Text(playerViewModel.sendspinConnected ? LocalizedStringKey("Connected") : LocalizedStringKey("Disconnected"))
                                .foregroundColor(playerViewModel.sendspinConnected ? .green : .red)
                        }

                        if playerViewModel.sendspinConnected {
                            Text("iOS device connected via Sendspin protocol. Audio will stream directly to this device.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Label("Player Name", systemImage: "pencil")
                            TextField("Name", text: $localPlayerName)
                                .multilineTextAlignment(.trailing)
                                .submitLabel(.done)
                                .onSubmit {
                                    sendspinClient.updatePlayerName(localPlayerName)
                                    Task {
                                        await client.renamePlayer(
                                            playerId: sendspinClient.universalPlayerId,
                                            name: localPlayerName
                                        )
                                    }
                                }
                        }
                    }
                } header: {
                    Text("Local Audio (Sendspin)")
                } footer: {
                    Text("Enable to receive audio streams via Sendspin.")
                }
                .onAppear {
                    localPlayerName = sendspinClient.playerName
                }

                Section {
                    if client.players.isEmpty {
                        if playerViewModel.isConnected {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 8)
                                Text("Loading players...")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Button {
                                playerViewModel.connectToServer()
                            } label: {
                                Label("Reconnect", systemImage: "wifi")
                            }
                        }
                    } else {
                        ForEach(client.visiblePlayers) { player in
                            Button {
                                Task { await selectPlayer(player) }
                            } label: {
                                HStack {
                                    Image(systemName: ProviderBrand(provider: player.provider, type: player.type, name: player.name).icon)
                                        .foregroundColor(ProviderBrand(provider: player.provider, type: player.type, name: player.name).color)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(player.name)
                                            .foregroundColor(.primary)
                                        Text(ProviderBrand(provider: player.provider, type: player.type, name: player.name).displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if player.playerId == client.currentPlayer?.playerId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                    if !player.available {
                                        Text("Offline")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            .disabled(!player.available)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Task { await client.removePlayer(player.playerId) }
                                }
                            }
                        }
                    }
                    if !client.hiddenPlayerIds.isEmpty {
                        Button("Show Hidden Players") {
                            client.unhideAllPlayers()
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Remote Player")
                } footer: {
                    Text("Select a player to send playback commands to.")
                }

                Section {
                    NavigationLink {
                        ProviderManagementView()
                    } label: {
                        Label("Providers", systemImage: "square.3.layers.3d")
                    }
                } header: {
                    Text("Music Sources")
                } footer: {
                    Text("Add, configure, or remove music providers and players.")
                }

                Section {
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("View the app's connection and playback logs for troubleshooting.")
                }

                Section {
                    HStack {
                        Label("App Version", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var connectionStatusText: LocalizedStringKey {
        if playerViewModel.isConnecting {
            return "Connecting..."
        } else if playerViewModel.isAuthenticating {
            return "Authenticating..."
        } else if playerViewModel.isConnected {
            return "Connected"
        } else {
            return "Disconnected"
        }
    }

    private var connectionStatusColor: Color {
        if playerViewModel.isConnected {
            return .green
        } else if playerViewModel.isConnecting || playerViewModel.isAuthenticating {
            return .orange
        } else {
            return .red
        }
    }

    private func selectPlayer(_ player: MAPlayer) async {
        if !playerViewModel.isConnected {
            playerViewModel.connectToServer()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        client.currentPlayer = player
        await client.switchPlayer(playerId: player.playerId)
    }
}

struct LogView: View {
    @ObservedObject private var logger = AppLogger.shared
    @State private var minLevel: LogLevel = .debug
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var showingShare = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var filteredEntries: [AppLogEntry] {
        logger.filteredEntries(minLevel: minLevel, searchText: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if filteredEntries.isEmpty {
                Spacer()
                ContentUnavailableView(
                    searchText.isEmpty ? "No Logs" : "No Results",
                    systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "No log entries recorded yet." : "Try a different search term or lower the minimum level.")
                )
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(filteredEntries) { entry in
                            logRow(entry)
                                .id(entry.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: filteredEntries.count) { _, _ in
                        if autoScroll, let last = filteredEntries.first {
                            withAnimation { proxy.scrollTo(last.id, anchor: .top) }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        autoScrollButton
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(filteredEntries.isEmpty)

                    Menu {
                        Button(role: .destructive) {
                            logger.clear()
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(logger.entries.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(text: logger.exportText(minLevel: minLevel, searchText: searchText))
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Search logs...", text: $searchText)
                        .font(.subheadline)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                levelPicker
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()
        }
        .background(.ultraThinMaterial)
    }

    private var levelPicker: some View {
        Menu {
            ForEach(LogLevel.allCases.reversed(), id: \.self) { level in
                Button {
                    minLevel = level
                } label: {
                    HStack {
                        Text(level.rawValue.capitalized)
                        if minLevel == level {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(levelColor(minLevel))
                    .frame(width: 8, height: 8)
                Text(minLevel.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(levelColor(minLevel).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var autoScrollButton: some View {
        Button {
            autoScroll.toggle()
        } label: {
            Image(systemName: autoScroll ? "arrow.down.to.line" : "arrow.up.to.line")
                .font(.caption)
                .foregroundColor(autoScroll ? .accentColor : .secondary)
                .padding(8)
                .background(.regularMaterial)
                .clipShape(Circle())
        }
        .padding(12)
    }

    private func logRow(_ entry: AppLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(levelColor(entry.level))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.level.rawValue)
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundColor(levelColor(entry.level))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(levelColor(entry.level).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if !entry.category.isEmpty {
                        Text(entry.category)
                            .font(.caption2.weight(.medium).monospaced())
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(Self.timeFormatter.string(from: entry.date))
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(PlayerViewModel())
            .environmentObject(LibraryViewModel())
    }
}

struct MiniPlayerView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    var expandAction: () -> Void
    @State private var rotationAngle: Double = 0
    @State private var marqueeAnimating = false
    @State private var marqueeOffset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var showingQueue = false
    private let marqueeSpeed: CGFloat = 25
    private let rotationDuration: Double = 8.0

    var body: some View {
        HStack(spacing: 10) {
            artworkView

            GeometryReader { container in
                HStack(spacing: 20) {
                    Text(displayText)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize()
                        .background(GeometryReader { t1 in
                            Color.clear.onAppear {
                                textWidth = t1.size.width
                                containerWidth = container.size.width
                                guard textWidth > containerWidth, textWidth > 0 else { return }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    marqueeAnimating = true
                                }
                            }
                        })

                    Text(displayText)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .offset(x: marqueeOffset)
                .animation(
                    marqueeAnimating ? .linear(duration: Double(textWidth + 20) / Double(marqueeSpeed)).repeatForever(autoreverses: false) : .default,
                    value: marqueeOffset
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: containerWidth > 0 && textWidth <= containerWidth ? .center : .leading)
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.94),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < -30 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            playerManager.next()
                        } else if value.translation.width > 30 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            playerManager.previous()
                        }
                    }
            )

            HStack(spacing: 6) {
                progressButton

                Button {
                    showingQueue = true
                } label: {
                    Image(systemName: "music.note.list")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Queue"))
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 54)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .onTapGesture { expandAction() }
        .onAppear {
            if playerManager.isPlaying { rotationAngle = 360 }
        }
        .onDisappear {
            marqueeAnimating = false
        }
        .onChange(of: playerManager.isPlaying) { playing in
            rotationAngle = playing ? 360 : 0
        }
        .onChange(of: displayText) { _, _ in
            marqueeAnimating = false
            marqueeOffset = 0
        }
        .onChange(of: marqueeAnimating) { _, animating in
            if animating {
                let wrapDistance = textWidth + 20
                marqueeOffset = -wrapDistance
            }
        }
        .sheet(isPresented: $showingQueue) {
            queueSheet
        }
    }

    private var progressButton: some View {
        let progress = playerManager.duration > 0 ? min(max(playerManager.currentTime / playerManager.duration, 0), 1) : 0

        return ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: 2.5)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))

            Button {
                playerManager.togglePlayPause()
            } label: {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
                    .offset(x: playerManager.isPlaying ? 0 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerManager.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
        }
    }

    private var queueSheet: some View {
        NavigationStack {
            if playerManager.queue.isEmpty {
                ContentUnavailableView(
                    "No Queue",
                    systemImage: "music.note.list",
                    description: Text("Add some songs from your library to start the queue.")
                )
            } else {
                List {
                    ForEach(Array(playerManager.queue.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: XonoraClient.shared.getImageURL(for: item.imageUrl, size: .thumbnail)) {
                                Color.clear
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(item.artistNames)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }
                    .onDelete { offsets in
                        for index in offsets { playerManager.removeFromQueue(at: index) }
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Queue")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingQueue = false }
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.85), .large])
    }

    private var displayText: String {
        guard let track = playerManager.currentTrack else { return NSLocalizedString("Not Playing", comment: "") }
        if track.artistNames.isEmpty { return track.name }
        return "\(track.name) - \(track.artistNames)"
    }

    // MARK: - Rotating Artwork (SwiftUI animation, GPU-accelerated)

    private var artworkView: some View {
        let url = XonoraClient.shared.getImageURL(
            for: playerManager.currentTrack?.imageUrl ?? playerManager.currentTrack?.album?.imageUrl,
            size: .thumbnail
        )

        return ZStack {
            CachedAsyncImage(url: url) {
                Color.clear
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .rotationEffect(.degrees(rotationAngle))
            .animation(
                playerManager.isPlaying ? .linear(duration: rotationDuration).repeatForever(autoreverses: false) : .default,
                value: rotationAngle
            )
        }
        .frame(width: 38, height: 38)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 12, height: 12)
        )
    }

}

