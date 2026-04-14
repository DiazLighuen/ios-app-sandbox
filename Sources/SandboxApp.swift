import SwiftUI
import GoogleSignIn

@main
struct SandboxApp: App {
    init() {
        print("🌐 [Config] host=\(AppConfig.apiHost) baseURL=\(HTTPClient.shared.baseURL)")
    }
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel   = AuthViewModel()
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var themeManager    = ThemeManager()
    @StateObject private var wsService       = WebSocketService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(languageManager.language)
                .environment(\.locale, Locale(identifier: languageManager.language))
                .environmentObject(authViewModel)
                .environmentObject(languageManager)
                .environmentObject(themeManager)
                .environmentObject(wsService)
                .preferredColorScheme(themeManager.colorScheme)
                .task {
                    await authViewModel.restoreGoogleSession()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveUnauthorized)) { _ in
                    authViewModel.handleUnauthorized()
                    wsService.disconnect()
                }
                // Connect WS when user logs in; disconnect on logout
                .onChange(of: authViewModel.isAuthenticated) { _, isAuth in
                    if isAuth { wsService.connect() } else { wsService.disconnect() }
                }
                // Handle app backgrounding / foregrounding
                .onChange(of: scenePhase) { _, phase in
                    guard authViewModel.isAuthenticated else { return }
                    switch phase {
                    case .active:      wsService.handleEnterForeground()
                    case .background:  wsService.handleEnterBackground()
                    case .inactive:    break
                    @unknown default:  break
                    }
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        if authViewModel.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}
