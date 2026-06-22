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
                    // Configure audio session asynchronously to avoid blocking startup
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.configureAudioSession()
                    }
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                print("[XonoraApp] App became active, refreshing state...")
                if playerViewModel.isConnected {
                    Task {
                        await XonoraClient.shared.fetchPlayers()
                        // Reconcile the player UI with the server's real state so the
                        // controls don't stay frozen after returning from another app.
                        PlayerManager.shared.syncStateFromServer()
                    }
                }
            } else if newPhase == .background {
                // Dismiss keyboard when going to background to prevent snapshotting errors
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
