import AVFoundation
import Combine
import MusicKit

/// 曲の30秒を再生する。どの画面からも同時に1曲だけ鳴らす。
/// - 流す範囲（clipStart）が選ばれていて Apple Music を契約していれば、曲をその位置から30秒だけ流す
/// - それ以外は Apple の試聴クリップ（約30秒）を流す（契約なしでも聴ける）
@MainActor
final class PreviewPlayer: ObservableObject {
    static let shared = PreviewPlayer()

    static let clipLength: Double = 30

    /// 再生中の曲の ID
    @Published private(set) var playingID: String?

    private var player: AVPlayer?
    private var usesMusicPlayer = false
    private var stopTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    func toggle(id: String, url: URL?, songID: String? = nil, clipStart: Double? = nil) {
        if playingID == id { stop(); return }
        stop()
        guard let songID, let clipStart, !songID.isEmpty, MusicAuthorization.currentStatus == .authorized else {
            playPreview(id: id, url: url)
            return
        }
        playingID = id
        startTask = Task { [weak self] in
            let ok = await self?.playFullSong(songID: songID, from: clipStart) ?? false
            guard !Task.isCancelled, let self, self.playingID == id else { return }
            if ok { self.scheduleStop() } else { self.playingID = nil; self.playPreview(id: id, url: url) }
        }
    }

    /// 選んだ範囲を試すとき：同じ曲でも止めずに、その位置から流し直す
    func play(id: String, url: URL?, songID: String, clipStart: Double) {
        stop()
        toggle(id: id, url: url, songID: songID, clipStart: clipStart)
    }

    private func playPreview(id: String, url: URL?) {
        guard let url else { return }
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
        scheduleStop()
    }

    /// Apple Music の曲を、指定した位置から流す（契約がなければ false）
    private func playFullSong(songID: String, from start: Double) async -> Bool {
        do {
            guard try await MusicSubscription.current.canPlayCatalogContent else { return false }
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songID))
            guard let song = try await request.response().items.first, !Task.isCancelled else { return false }
            let music = ApplicationMusicPlayer.shared
            music.queue = [song]
            try await music.prepareToPlay()
            guard !Task.isCancelled else { return false }
            music.playbackTime = start
            try await music.play()
            usesMusicPlayer = true
            return true
        } catch {
            return false
        }
    }

    private func scheduleStop() {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.clipLength * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        stopTask?.cancel()
        stopTask = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        if usesMusicPlayer {
            ApplicationMusicPlayer.shared.stop()
            usesMusicPlayer = false
        }
        playingID = nil
    }
}
