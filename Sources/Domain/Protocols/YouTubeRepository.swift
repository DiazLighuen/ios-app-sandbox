import Foundation

protocol YouTubeRepository {
    func fetchSubscriptions(pageToken: String?) async throws -> SubscriptionsPage
    func fetchHome(page: Int) async throws -> FeedPage
    func fetchLive() async throws -> LivePage
    func search(query: String, type: String, pageToken: String?) async throws -> SearchPage
    func fetchVideo(id: String) async throws -> YouTubeVideoDetail
}
