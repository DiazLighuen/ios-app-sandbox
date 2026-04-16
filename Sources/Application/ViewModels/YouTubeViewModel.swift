import Foundation
import Combine

@MainActor
final class YouTubeViewModel: ObservableObject {
    // Tab selection
    @Published var selectedTab: YouTubeTab = .home

    // Home
    @Published private(set) var homeFeed: [YouTubeVideo] = []
    @Published private(set) var homeIsLoading = false
    @Published private(set) var homeHasMore = false
    private var homePage = 1

    // Search
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [YouTubeSearchItem] = []
    @Published private(set) var searchIsLoading = false
    @Published private(set) var searchHasMore = false
    private var searchNextToken: String? = nil

    // Subscriptions
    @Published private(set) var subscriptions: [YouTubeChannel] = []
    @Published private(set) var subscriptionsIsLoading = false
    @Published private(set) var subscriptionsHasMore = false
    private var subscriptionsNextToken: String? = nil

    // Live
    @Published private(set) var liveStreams: [YouTubeLiveStream] = []
    @Published private(set) var liveIsLoading = false

    @Published var error: String?
    @Published var needsYouTubeAuth = false

    private let repository: YouTubeRepository

    init(repository: YouTubeRepository = YouTubeAPI()) {
        self.repository = repository
    }

    func loadHome(reset: Bool = false) async {
        if reset { homePage = 1; homeFeed = [] }
        guard !homeIsLoading else { return }
        homeIsLoading = true
        defer { homeIsLoading = false }
        do {
            let page = try await repository.fetchHome(page: homePage)
            homeFeed.append(contentsOf: page.items)
            homeHasMore = page.hasMore
            if page.hasMore { homePage += 1 }
        } catch {
            handle(error)
        }
    }

    func loadMoreHome() async {
        guard homeHasMore && !homeIsLoading else { return }
        await loadHome()
    }

    func search(reset: Bool = false) async {
        guard !searchQuery.isEmpty else { searchResults = []; return }
        if reset { searchNextToken = nil; searchResults = [] }
        guard !searchIsLoading else { return }
        searchIsLoading = true
        defer { searchIsLoading = false }
        do {
            let page = try await repository.search(query: searchQuery, type: "video", pageToken: searchNextToken)
            searchResults.append(contentsOf: page.items)
            searchNextToken = page.nextPageToken
            searchHasMore = page.hasMore
        } catch {
            handle(error)
        }
    }

    func loadMoreSearch() async {
        guard searchHasMore && !searchIsLoading else { return }
        await search()
    }

    func loadSubscriptions(reset: Bool = false) async {
        if reset { subscriptionsNextToken = nil; subscriptions = [] }
        guard !subscriptionsIsLoading else { return }
        subscriptionsIsLoading = true
        defer { subscriptionsIsLoading = false }
        do {
            let page = try await repository.fetchSubscriptions(pageToken: subscriptionsNextToken)
            subscriptions.append(contentsOf: page.items)
            subscriptionsNextToken = page.nextPageToken
            subscriptionsHasMore = page.hasMore
        } catch {
            handle(error)
        }
    }

    func loadMoreSubscriptions() async {
        guard subscriptionsHasMore && !subscriptionsIsLoading else { return }
        await loadSubscriptions()
    }

    func loadLive() async {
        guard !liveIsLoading else { return }
        liveIsLoading = true
        defer { liveIsLoading = false }
        do {
            let page = try await repository.fetchLive()
            liveStreams = page.items
        } catch {
            handle(error)
        }
    }

    /// Called after YouTube account is successfully linked. Clears the auth prompt and retries.
    func retryAfterAuth() async {
        needsYouTubeAuth = false
        switch selectedTab {
        case .home:          await loadHome(reset: true)
        case .live:          await loadLive()
        case .subscriptions: await loadSubscriptions(reset: true)
        case .search:        if !searchQuery.isEmpty { await search(reset: true) }
        }
    }

    private func handle(_ error: Error) {
        if case AppError.unauthorized = error {
            needsYouTubeAuth = true
        } else {
            self.error = error.localizedDescription
        }
    }
}

enum YouTubeTab: String, CaseIterable {
    case home, search, subscriptions, live

    var label: String {
        switch self {
        case .home:          return "Home"
        case .search:        return "Search"
        case .subscriptions: return "Subscriptions"
        case .live:          return "Live"
        }
    }
}
