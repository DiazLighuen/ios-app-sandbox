import Foundation

enum AppConfig {
    /// Active backend host — injected via xcconfig (Debug = localhost, Release = production).
    static let apiHost: String =
        Bundle.main.object(forInfoDictionaryKey: "API_BASE_HOST") as? String ?? "localhost"

    /// Web OAuth 2.0 Client ID from Google Cloud Console.
    /// Required so GIDSignIn returns a serverAuthCode for YouTube token exchange.
    /// console.cloud.google.com → APIs & Services → Credentials → OAuth 2.0 Client IDs (type: Web application)
    static let googleServerClientID = "304393689064-sdj3q6pk099kvivgbrrnqiuc94b05s8k.apps.googleusercontent.com"
}
