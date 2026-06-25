import SwiftUI
import AVFoundation

@main
struct XonoraApp: App {
    @StateObject private var playerViewModel = PlayerViewModel()
    @StateObject private var libraryViewModel = LibraryViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.75)
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(named: "AccentColor")
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(named: "AccentColor") ?? .systemBlue]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = UIColor(named: "AccentColor")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playerViewModel)
                .environmentObject(libraryViewModel)
                .onAppear {
                    Task { @MainActor in
                        self.configureAudioSession()
                    }
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                print("[XonoraApp] App became active, refreshing state...")
                
                // ============================================================
                // Step 1: Resume local audio engine FIRST — drains the 30s PCM
                // ring buffer so playback is instant and gapless.
                // ============================================================
                SendspinClient.shared.resumePlayback()
                
                // ============================================================
                // Step 2: Reconnect XonoraClient if connection was lost during
                // suspension. Uses force:false so it won't tear down a live
                // connection (and won't destroy the Sendspin AudioPlayer).
                // ============================================================
                if !playerViewModel.isConnected {
                    playerViewModel.connectToServer(force: false)
                }
                
                // ============================================================
                // Step 3: Async state sync — happens in background while audio
                // is already playing from local buffer.
                // ============================================================
                if playerViewModel.isConnected {
                    Task {
                        await XonoraClient.shared.fetchPlayers()
                        PlayerManager.shared.syncStateFromServer()
                    }
                }
            } else if newPhase == .background {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
}
