import Foundation

struct DashboardData: Decodable {
    let containers: ContainersBlock
    let youtubeQuota: YoutubeQuota?

    enum CodingKeys: String, CodingKey {
        case containers
        case youtubeQuota = "youtube_quota"
    }

    struct ContainersBlock: Decodable {
        let available: Bool
        let items: [ContainerInfo]
    }

    struct YoutubeQuota: Decodable {
        let used: Int
        let limit: Int
        let remaining: Int
        let percent: Double
        let resetDate: String

        enum CodingKeys: String, CodingKey {
            case used, limit, remaining, percent
            case resetDate = "reset_date"
        }
    }
}

struct ContainerInfo: Identifiable, Decodable {
    let id: String
    let name: String
    let image: String
    let status: String
    let running: Bool
    let cpuPct:   Double
    let memRss:   Int
    let memLimit: Int
    let memPct:   Double
    let netRx:    Int
    let netTx:    Int
    let blkRead:  Int
    let blkWrite: Int
    let pids:     Int

    enum CodingKeys: String, CodingKey {
        case id, name, image, status, running, pids
        case cpuPct   = "cpu_pct"
        case memRss   = "mem_rss"
        case memLimit = "mem_limit"
        case memPct   = "mem_pct"
        case netRx    = "net_rx"
        case netTx    = "net_tx"
        case blkRead  = "blk_read"
        case blkWrite = "blk_write"
    }

    var cpuFormatted: String { String(format: "%.1f%%", cpuPct) }
    var memFormatted: String { "\(formatBytes(memRss)) / \(formatBytes(memLimit)) (\(String(format: "%.1f%%", memPct)))" }
    var netFormatted: String { "↑ \(formatBytes(netTx))  ↓ \(formatBytes(netRx))" }
    var blkFormatted: String { "R \(formatBytes(blkRead))  W \(formatBytes(blkWrite))" }
}

func formatBytes(_ bytes: Int) -> String {
    let kb = Double(bytes) / 1_024
    let mb = kb / 1_024
    let gb = mb / 1_024
    if gb >= 1   { return String(format: "%.1f GB", gb) }
    if mb >= 0.1 { return String(format: "%.1f MB", mb) }
    if kb >= 0.1 { return String(format: "%.1f KB", kb) }
    return "\(bytes) B"
}
