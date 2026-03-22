import SwiftUI
import UserNotifications

struct NotificationsView: View {
    @ObservedObject var service: WebSocketService
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Group {
                if authStatus == .denied {
                    permissionDeniedView
                } else if service.messages.isEmpty {
                    ContentUnavailableView(
                        "events.empty.title".loc,
                        systemImage: "bell.slash",
                        description: Text(service.isConnected
                            ? "events.waiting".loc
                            : "events.noConnection".loc)
                    )
                } else {
                    List(service.messages) { msg in
                        WSMessageRow(message: msg)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("events.title".loc)
            .toolbar {
                ToolbarItem(placement: .status) {
                    Label(
                        service.isConnected ? "events.connected".loc : "events.disconnected".loc,
                        systemImage: service.isConnected ? "circle.fill" : "circle"
                    )
                    .foregroundStyle(service.isConnected ? .green : .red)
                    .font(.caption)
                }
            }
        }
        .task { await checkAndRequestPermission() }
    }

    // MARK: - Permission

    private func checkAndRequestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authStatus = settings.authorizationStatus

        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authStatus = granted ? .authorized : .denied
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("events.notif.allow".loc)
                .font(.headline)
            Text("events.notif.desc".loc)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("events.notif.open".loc) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct WSMessageRow: View {
    let message: WSMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(message.message)
                    .font(.subheadline)
                HStack {
                    Text(message.type)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(message.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var severityColor: Color {
        switch message.severity {
        case "critical": return .red
        case "warning":  return .yellow
        default:         return .green
        }
    }
}
