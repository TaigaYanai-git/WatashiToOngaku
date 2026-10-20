import AVFoundation
import Combine

/// Apple Music の試聴クリップ（約30秒）を再生する。どの画面からも同時に1曲だけ鳴らす。
@MainActor
final class PreviewPlayer: ObservableObject {
    static let shared = PreviewPlayer()

    /// 再生中の曲の ID
    @Published private(set) var playingID: String?

    private var player: AVPlayer?
    private var stopTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    func toggle(id: String, url: URL?) {
        if playingID == id { stop(); return }
        guard let url else { return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        playingID = id
        player.play()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.stop() } }
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        playingID = nil
    }
}
