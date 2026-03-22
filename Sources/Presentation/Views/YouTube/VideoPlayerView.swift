import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoId: String
    @StateObject private var viewModel = YouTubePlayerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Video player
                VideoPlayer(player: viewModel.player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(.black)

                if let detail = viewModel.detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(detail.title)
                                .font(.headline)
                            HStack {
                                Text(detail.channelName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let views = detail.viewCount {
                                    Text("\(YouTubeVideo.formatViewCount(views)) views")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            if let desc = detail.descriptionText, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(5)
                            }
                        }
                        .padding()
                    }
                } else if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else if let err = viewModel.error {
                    Spacer()
                    ContentUnavailableView(
                        "Playback Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err)
                    )
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                    }
                }

            }
        }
        .task { await viewModel.load(videoId: videoId) }
    }
}
