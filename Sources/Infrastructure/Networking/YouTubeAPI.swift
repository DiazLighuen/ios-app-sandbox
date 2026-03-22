import Foundation
import GoogleSignIn

final class YouTubeAPI: YouTubeRepository {
    private let client = HTTPClient.shared

    private func googleHeaders() async throws -> [String: String] {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw AppError.unauthorized
        }
        let refreshed = try await user.refreshTokensIfNeeded()
        return ["X-Google-Token": refreshed.accessToken.tokenString]
    }

    func fetchSubscriptions(pageToken: String?) async throws -> SubscriptionsPage {
        let headers = try await googleHeaders()
        var path = "/api/youtube/subscriptions"
        if let token = pageToken {
            path += "?page_token=\(token)"
        }
        return try await client.request(path, additionalHeaders: headers)
    }

    func fetchHome(page: Int) async throws -> FeedPage {
        let headers = try await googleHeaders()
        return try await client.request("/api/youtube/home?page=\(page)", additionalHeaders: headers)
    }

    func fetchLive() async throws -> LivePage {
        let headers = try await googleHeaders()
        return try await client.request("/api/youtube/live", additionalHeaders: headers)
    }

    func search(query: String, type: String = "video", pageToken: String?) async throws -> SearchPage {
        let headers = try await googleHeaders()
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var path = "/api/youtube/search?q=\(encoded)&type=\(type)"
        if let token = pageToken {
            path += "&page_token=\(token)"
        }
        return try await client.request(path, additionalHeaders: headers)
    }

    func fetchVideo(id: String) async throws -> YouTubeVideoDetail {
        let headers = try await googleHeaders()
        return try await client.request("/api/youtube/video/\(id)", additionalHeaders: headers)
    }
}
