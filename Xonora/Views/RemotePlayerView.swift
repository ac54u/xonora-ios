import SwiftUI

struct RemotePlayerView: View {
    @EnvironmentObject var playerViewModel: PlayerViewModel
    @ObservedObject private var client = XonoraClient.shared
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !playerViewModel.isConnected {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Not connected to server")
                                .foregroundColor(.secondary)
                            Button {
                                connectAndReload()
                            } label: {
                                if isConnecting {
                                    HStack {
                                        ProgressView().scaleEffect(0.8)
                                        Text("Connecting...")
                                    }
                                } else {
                                    Label("Reconnect", systemImage: "wifi")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isConnecting)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
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
                            Text("Connect to a server to see players")
                                .foregroundColor(.secondary)
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
                    if playerViewModel.sendspinEnabled {
                        HStack {
                            Label("Sendspin Status", systemImage: playerViewModel.sendspinConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Spacer()
                            Text(playerViewModel.sendspinConnected ? LocalizedStringKey("Connected") : LocalizedStringKey("Disconnected"))
                                .foregroundColor(playerViewModel.sendspinConnected ? .green : .red)
                        }
                    }
                } header: {
                    Text("Local Audio (Sendspin)")
                }
            }
            .navigationTitle("Remote Player")
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func connectAndReload() {
        guard !isConnecting else { return }
        isConnecting = true
        playerViewModel.connectToServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isConnecting = false
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
