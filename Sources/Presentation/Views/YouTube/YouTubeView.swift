import SwiftUI

struct YouTubeView: View {
    @StateObject private var viewModel = YouTubeViewModel()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var selectedVideoId: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Tab", selection: $viewModel.selectedTab) {
                    ForEach(YouTubeTab.allCases, id: \.self) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Content
                switch viewModel.selectedTab {
                case .home:
                    HomeFeedView(viewModel: viewModel, selectedVideoId: $selectedVideoId)
                case .search:
                    SearchView(viewModel: viewModel, selectedVideoId: $selectedVideoId)
                case .live:
                    LiveView(viewModel: viewModel, selectedVideoId: $selectedVideoId)
                case .subscriptions:
                    SubscriptionsView(viewModel: viewModel)
                }
            }
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .navigationDestination(item: $selectedVideoId) { id in
                VideoPlayerView(videoId: id)
            }
            .overlay(alignment: .bottom) {
                if viewModel.needsYouTubeAuth {
                    YouTubeAuthBanner {
                        guard let root = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .first?.windows.first?.rootViewController else { return }
                        Task {
                            await authViewModel.linkYouTubeAccount(presenting: root)
                            if authViewModel.error == nil {
                                await viewModel.retryAfterAuth()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct YouTubeAuthBanner: View {
    let onLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cuenta de YouTube no vinculada")
                .font(.subheadline.weight(.semibold))
            Text("Seleccioná la cuenta o canal de YouTube que querés usar.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: onLink) {
                Label("Vincular cuenta de YouTube", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

// MARK: - Home Feed

private struct HomeFeedView: View {
    @ObservedObject var viewModel: YouTubeViewModel
    @Binding var selectedVideoId: String?

    var body: some View {
        Group {
            if viewModel.homeFeed.isEmpty && viewModel.homeIsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.homeFeed.isEmpty {
                ContentUnavailableView(
                    "No Videos",
                    systemImage: "play.rectangle",
                    description: Text("Your feed is empty.")
                )
            } else {
                List {
                    ForEach(viewModel.homeFeed) { video in
                        Button {
                            selectedVideoId = video.id
                        } label: {
                            VideoRowView(video: video)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if video.id == viewModel.homeFeed.last?.id {
                                Task { await viewModel.loadMoreHome() }
                            }
                        }
                    }
                    if viewModel.homeIsLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await viewModel.loadHome(reset: true) }
        .refreshable { await viewModel.loadHome(reset: true) }
    }
}

// MARK: - Search

private struct SearchView: View {
    @ObservedObject var viewModel: YouTubeViewModel
    @Binding var selectedVideoId: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search videos or channels", text: $viewModel.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.search(reset: true) }
                    }
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        Task { await viewModel.search(reset: true) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.bottom, 8)

            if viewModel.searchResults.isEmpty && viewModel.searchIsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
            } else if viewModel.searchResults.isEmpty {
                ContentUnavailableView(
                    "Search YouTube",
                    systemImage: "magnifyingglass",
                    description: Text("Enter a query to search for videos or channels.")
                )
            } else {
                List {
                    ForEach(viewModel.searchResults) { item in
                        searchItemRow(item)
                            .onAppear {
                                if item.id == viewModel.searchResults.last?.id {
                                    Task { await viewModel.loadMoreSearch() }
                                }
                            }
                    }
                    if viewModel.searchIsLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func searchItemRow(_ item: YouTubeSearchItem) -> some View {
        switch item.content {
        case .video(let video):
            Button {
                selectedVideoId = video.id
            } label: {
                VideoRowView(video: video)
            }
            .buttonStyle(.plain)
        case .channel(let channel):
            HStack(spacing: 12) {
                AsyncImage(url: channel.avatar) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color(.systemFill)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.subheadline.weight(.medium))
                    if let count = channel.subscriberCount {
                        Text("\(YouTubeVideo.formatViewCount(count)) subscribers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Live

private struct LiveView: View {
    @ObservedObject var viewModel: YouTubeViewModel
    @Binding var selectedVideoId: String?

    var body: some View {
        Group {
            if viewModel.liveStreams.isEmpty && viewModel.liveIsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.liveStreams.isEmpty {
                ContentUnavailableView(
                    "No Live Streams",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("None of your subscribed channels are live right now.")
                )
            } else {
                List(viewModel.liveStreams) { stream in
                    Button {
                        selectedVideoId = stream.id
                    } label: {
                        liveStreamRow(stream)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .task { await viewModel.loadLive() }
        .refreshable { await viewModel.loadLive() }
    }

    @ViewBuilder
    private func liveStreamRow(_ stream: YouTubeLiveStream) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: stream.thumbnail) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color(.systemFill)
                    }
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .frame(width: 120, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text(stream.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(stream.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let viewers = stream.viewerCount {
                    Text("\(YouTubeVideo.formatViewCount(viewers)) watching")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Subscriptions

private struct SubscriptionsView: View {
    @ObservedObject var viewModel: YouTubeViewModel

    var body: some View {
        Group {
            if viewModel.subscriptions.isEmpty && viewModel.subscriptionsIsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.subscriptions.isEmpty {
                ContentUnavailableView(
                    "No Subscriptions",
                    systemImage: "person.badge.plus",
                    description: Text("Your subscribed channels will appear here.")
                )
            } else {
                List {
                    ForEach(viewModel.subscriptions) { channel in
                        channelRow(channel)
                            .onAppear {
                                if channel.id == viewModel.subscriptions.last?.id {
                                    Task { await viewModel.loadMoreSubscriptions() }
                                }
                            }
                    }
                    if viewModel.subscriptionsIsLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await viewModel.loadSubscriptions(reset: true) }
        .refreshable { await viewModel.loadSubscriptions(reset: true) }
    }

    @ViewBuilder
    private func channelRow(_ channel: YouTubeChannel) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: channel.avatar) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color(.systemFill)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.subheadline.weight(.medium))
                if let count = channel.subscriberCount {
                    Text("\(YouTubeVideo.formatViewCount(count)) subscribers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
