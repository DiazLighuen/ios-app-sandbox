import Foundation
import UIKit
import UserNotifications

@MainActor
final class WebSocketService: ObservableObject {
    @Published private(set) var messages: [WSMessage] = []
    @Published private(set) var isConnected = false

    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    /// Background task token to keep the WS alive briefly when the app is backgrounded.
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    private var wsURL: URL? {
        guard let token = (try? KeychainService.shared.getToken()) ?? nil else { return nil }
        let host = AppConfig.apiHost
        let scheme = host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1") ? "ws" : "wss"
        return URL(string: "\(scheme)://\(host)/ws?token=\(token)")
    }

    // MARK: - Lifecycle

    func connect() {
        guard !isConnected, task == nil else { return }
        guard let url = wsURL else { return }

        task = session.webSocketTask(with: url)
        task?.resume()
        isConnected = true
        receiveNextMessage()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        isConnected = false
        endBackgroundTask()
    }

    /// Call when the app scene transitions to background.
    /// Requests up to ~30 s of background execution time so WS keeps running briefly.
    func handleEnterBackground() {
        guard bgTaskID == .invalid else { return }
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "ws-keepalive") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    /// Call when the app scene returns to foreground — reconnects if the WS was dropped.
    func handleEnterForeground() {
        endBackgroundTask()
        if !isConnected { connect() }
    }

    // MARK: - Private

    private func endBackgroundTask() {
        guard bgTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTaskID)
        bgTaskID = .invalid
    }

    private func receiveNextMessage() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    let raw: String? = switch message {
                    case .string(let text): text
                    case .data(let data):   String(data: data, encoding: .utf8)
                    @unknown default:       nil
                    }
                    if let raw, let parsed = WSMessage(raw: raw) {
                        self?.messages.insert(parsed, at: 0)
                        self?.postLocalNotification(for: parsed)
                    }
                    self?.receiveNextMessage()

                case .failure(let error):
                    self?.isConnected = false
                    self?.task = nil
                    let code = (error as? URLError)?.errorCode
                    if code == 4001 || code == 4003 {
                        NotificationCenter.default.post(name: .didReceiveUnauthorized, object: nil)
                    }
                }
            }
        }
    }

    /// Posts a local notification. The UNUserNotificationCenterDelegate in AppDelegate
    /// ensures banners are shown even when the app is in the foreground.
    private func postLocalNotification(for msg: WSMessage) {
        let content = UNMutableNotificationContent()
        content.title = msg.type
        content.body  = msg.message
        content.sound = msg.severity == "critical" ? .defaultCritical : .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: msg.id, content: content, trigger: nil)
        )
    }
}

// MARK: - WSMessage

struct WSMessage: Identifiable {
    let id: String
    let type: String
    let severity: String
    let message: String
    let timestamp: Date

    init?(raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id   = json["id"] as? String,
              let type = json["type"] as? String,
              let msg  = json["message"] as? String
        else { return nil }

        self.id       = id
        self.type     = type
        self.severity = json["severity"] as? String ?? "info"
        self.message  = msg

        let tsRaw = json["timestamp"] as? String ?? ""
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = iso.date(from: tsRaw) ?? Date()
    }
}
