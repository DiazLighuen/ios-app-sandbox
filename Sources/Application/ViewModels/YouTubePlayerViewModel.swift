import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class YouTubePlayerViewModel: ObservableObject {
    @Published private(set) var detail: YouTubeVideoDetail?
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published private(set) var isPlaying = false


    let player = AVPlayer()
    private let repository: YouTubeRepository
    private var itemObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?

    init(repository: YouTubeRepository = YouTubeAPI()) {
        self.repository = repository
        setupRemoteCommands()
        rateObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    func load(videoId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let videoDetail = try await repository.fetchVideo(id: videoId)
            detail = videoDetail
            // Build proxy URL: /api/youtube/stream/{id}
            // No enviamos quality — el backend elige el mejor formato disponible via yt-dlp.
            // Los quality labels de Invidious (formatStreams) no siempre coinciden con los de yt-dlp.
            let proxyPath = "/api/youtube/stream/\(videoId)"
            let url = URL(string: HTTPClient.shared.baseURL.absoluteString + proxyPath)!
            print("▶️ [Player] Proxy URL: \(url)")
            let token = try? KeychainService.shared.getToken()
            var headers: [String: String] = [:]
            if let token { headers["Authorization"] = "Bearer \(token)" }
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item = AVPlayerItem(asset: asset)

            itemObservation = item.observe(\.status) { [weak self] (item: AVPlayerItem, _) in
                Task { @MainActor [weak self] in
                    switch item.status {
                    case .readyToPlay:
                        print("✅ [Player] readyToPlay — starting playback")
                        self?.activateAudioSession()
                        self?.player.play()
                        self?.isPlaying = true
                    case .failed:
                        print("🔴 [Player] Item failed: \(item.error as Any)")
                        self?.error = item.error?.localizedDescription ?? "Unknown player error"
                        self?.isPlaying = false
                    default:
                        print("🟡 [Player] status: \(item.status.rawValue)")
                    }
                }
            }
            player.replaceCurrentItem(with: item)
            updateNowPlaying(videoDetail)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }


    private func activateAudioSession() {
        // Session category is configured in AppDelegate at launch.
        // Re-activate here in case another app (e.g. phone call) deactivated it.
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player.play()
                self?.isPlaying = true
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player.pause()
                self?.isPlaying = false
            }
            return .success
        }
    }

    private func updateNowPlaying(_ video: YouTubeVideoDetail) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = video.title
        info[MPMediaItemPropertyArtist] = video.channelName
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    deinit {
        itemObservation = nil
        rateObservation = nil
        player.pause()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
