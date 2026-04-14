import Foundation

enum AppConfig {
    static let apiHost: String =
        Bundle.main.object(forInfoDictionaryKey: "API_BASE_HOST") as? String ?? "localhost"
}
