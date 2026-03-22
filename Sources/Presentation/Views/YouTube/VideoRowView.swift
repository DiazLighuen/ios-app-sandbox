import SwiftUI

struct VideoRowView: View {
    let video: YouTubeVideo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail with duration badge
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: video.thumbnail) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color(.systemFill)
                    }
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(video.durationFormatted)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .frame(width: 120, height: 68)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(video.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if video.viewCount != nil {
                        Text("\(video.viewCountFormatted) views")
                    }
                    Text("•")
                    Text(video.publishedAt, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
