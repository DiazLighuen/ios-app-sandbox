import Foundation

// MARK: - Channel
struct YouTubeChannel: Identifiable, Decodable {
    let id: String
    let name: String
    let avatar: URL?
    let subscriberCount: Int?
    enum CodingKeys: String, CodingKey {
        case id = "channel_id"
        case name, avatar
        case subscriberCount = "subscriber_count"
    }
}

// MARK: - Video
struct YouTubeVideo: Identifiable, Decodable {
    let id: String
    let title: String
    let channelId: String
    let channelName: String
    let thumbnail: URL?
    let duration: String   // ISO 8601 e.g. "PT4M32S"
    let publishedAt: Date
    let viewCount: Int?
    enum CodingKeys: String, CodingKey {
        case id, title, thumbnail, duration
        case channelId   = "channel_id"
        case channelName = "channel_name"
        case publishedAt = "published_at"
        case viewCount   = "view_count"
    }

    /// Parses ISO 8601 duration like PT1H4M32S → "1:04:32", PT4M32S → "4:32", PT45S → "0:45"
    var durationFormatted: String {
        Self.formatDuration(duration)
    }

    static func formatDuration(_ iso: String) -> String {
        // Strip the leading "PT"
        var s = iso
        guard s.hasPrefix("PT") else { return iso }
        s = String(s.dropFirst(2))

        var hours = 0
        var minutes = 0
        var seconds = 0

        if let hRange = s.range(of: "H") {
            hours = Int(s[s.startIndex..<hRange.lowerBound]) ?? 0
            s = String(s[hRange.upperBound...])
        }
        if let mRange = s.range(of: "M") {
            minutes = Int(s[s.startIndex..<mRange.lowerBound]) ?? 0
            s = String(s[mRange.upperBound...])
        }
        if let sRange = s.range(of: "S") {
            seconds = Int(s[s.startIndex..<sRange.lowerBound]) ?? 0
        }

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Formats view counts: <1K → "123", <1M → "450K", else → "1.2M"
    var viewCountFormatted: String {
        guard let count = viewCount else { return "" }
        return Self.formatViewCount(count)
    }

    static func formatViewCount(_ count: Int) -> String {
        switch count {
        case ..<1_000:
            return "\(count)"
        case 1_000..<1_000_000:
            let k = Double(count) / 1_000.0
            if k == Double(Int(k)) {
                return "\(Int(k))K"
            }
            return String(format: "%.1fK", k)
        default:
            let m = Double(count) / 1_000_000.0
            if m == Double(Int(m)) {
                return "\(Int(m))M"
            }
            return String(format: "%.1fM", m)
        }
    }
}

// MARK: - Video Detail (extends Video fields + streams)
struct YouTubeVideoDetail: Decodable {
    let id: String
    let title: String
    let channelId: String
    let channelName: String
    let thumbnail: URL?
    let duration: String
    let publishedAt: Date
    let viewCount: Int?
    let descriptionText: String?
    let formatStreams: [FormatStream]
    let audioStreams: [AudioStream]
    let videoStreams: [VideoStream]

    enum CodingKeys: String, CodingKey {
        case id, title, thumbnail, duration
        case channelId      = "channel_id"
        case channelName    = "channel_name"
        case publishedAt    = "published_at"
        case viewCount      = "view_count"
        case descriptionText = "description_text"
        case formatStreams   = "format_streams"
        case audioStreams    = "audio_streams"
        case videoStreams    = "video_streams"
    }

    /// Best combined mp4 stream URL for simple AVPlayer playback
    var bestPlaybackURL: URL? {
        formatStreams.first(where: { $0.ext == "mp4" })?.url ?? formatStreams.first?.url
    }

    struct FormatStream: Decodable {
        let url: URL
        let quality: String
        let ext: String
        let filesize: Int?
    }

    struct AudioStream: Decodable {
        let url: URL
        let bitrate: Double
        let ext: String
    }

    struct VideoStream: Decodable {
        let url: URL
        let quality: String
        let ext: String
    }
}

// MARK: - Live Stream
struct YouTubeLiveStream: Identifiable, Decodable {
    let id: String
    let platform: String
    let title: String
    let channelId: String
    let channelName: String
    let thumbnail: URL?
    let viewerCount: Int?
    let startedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, platform, title, thumbnail
        case channelId   = "channel_id"
        case channelName = "channel_name"
        case viewerCount = "viewer_count"
        case startedAt   = "started_at"
    }
}

// MARK: - Search Item (oneOf Video | Channel)
// Discriminated by presence of "duration" field (only Video has it)
struct YouTubeSearchItem: Identifiable {
    enum Content { case video(YouTubeVideo); case channel(YouTubeChannel) }
    let content: Content
    var id: String {
        switch content {
        case .video(let v): return "v_\(v.id)"
        case .channel(let c): return "c_\(c.id)"
        }
    }
}

extension YouTubeSearchItem: Decodable {
    private struct RawItem: Decodable {
        // Video fields
        let id: String?
        let title: String?
        let channelId: String?
        let channelName: String?
        let duration: String?
        let publishedAt: Date?
        let viewCount: Int?
        let thumbnail: URL?
        // Channel fields
        let name: String?
        let avatar: URL?
        let subscriberCount: Int?
        enum CodingKeys: String, CodingKey {
            case id, title, thumbnail, duration, name, avatar
            case channelId       = "channel_id"
            case channelName     = "channel_name"
            case publishedAt     = "published_at"
            case viewCount       = "view_count"
            case subscriberCount = "subscriber_count"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try RawItem(from: decoder)
        if let videoId = raw.id, let title = raw.title,
           let channelId = raw.channelId, let channelName = raw.channelName,
           let duration = raw.duration, let publishedAt = raw.publishedAt {
            let video = YouTubeVideo(
                id: videoId,
                title: title,
                channelId: channelId,
                channelName: channelName,
                thumbnail: raw.thumbnail,
                duration: duration,
                publishedAt: publishedAt,
                viewCount: raw.viewCount
            )
            content = .video(video)
        } else if let name = raw.name, let channelId = raw.channelId {
            let channel = YouTubeChannel(
                id: channelId,
                name: name,
                avatar: raw.avatar,
                subscriberCount: raw.subscriberCount
            )
            content = .channel(channel)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Cannot decode as Video or Channel")
            )
        }
    }
}

// MARK: - Page wrappers
struct SubscriptionsPage: Decodable {
    let items: [YouTubeChannel]
    let nextPageToken: String?
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case items
        case nextPageToken = "next_page_token"
        case hasMore       = "has_more"
    }
}

struct FeedPage: Decodable {
    let items: [YouTubeVideo]
    let page: Int
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case items, page
        case hasMore = "has_more"
    }
}

struct SearchPage: Decodable {
    let items: [YouTubeSearchItem]
    let nextPageToken: String?
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case items
        case nextPageToken = "next_page_token"
        case hasMore       = "has_more"
    }
}

struct LivePage: Decodable {
    let items: [YouTubeLiveStream]
}
