import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    // Owned by SandboxApp so it survives language-change rebuilds
    @EnvironmentObject private var wsService: WebSocketService

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("tab.dashboard".loc, systemImage: "chart.bar") }

            NotificationsView(service: wsService)
                .tabItem { Label("tab.events".loc, systemImage: "bell") }

            UsersView()
                .tabItem { Label("tab.users".loc, systemImage: "person.2") }

            YouTubeView()
                .tabItem { Label("Watch", systemImage: "play.tv") }

            SudokuTabView()
                .tabItem { Label("Sudoku", systemImage: "squareshape.split.3x3") }

            SettingsView()
                .tabItem { Label("tab.settings".loc, systemImage: "gear") }
        }
    }
}
