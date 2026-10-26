import MusicKit
import SwiftUI

/// ミュージック（SystemMusicPlayer）で今の曲。アプリ内の一覧で「再生中」を示したり、操作バーを出したりするのに使う
struct NowPlayingSong: Equatable {
    let id: String?
    let title: String
    let artist: String?
    let isPlaying: Bool

    /// 今の曲（一時停止中も含む）。止まっていれば nil
    static func current(queue: MusicPlayer.Queue, state: MusicPlayer.State) -> NowPlayingSong? {
        let status = state.playbackStatus
        guard status == .playing || status == .paused, let entry = queue.currentEntry else { return nil }
        if case .song(let song)? = entry.item {
            return NowPlayingSong(id: song.id.rawValue, title: song.title, artist: song.artistName, isPlaying: status == .playing)
        }
        return NowPlayingSong(id: nil, title: entry.title, artist: entry.subtitle, isPlaying: status == .playing)
    }

    func matches(songID: String, title: String, artist: String) -> Bool {
        if let id { return id == songID }
        return self.title == title && self.artist == artist
    }
}

/// 一覧の曲を流しているあいだ下に出す、前の曲・再生／一時停止・次の曲の操作バー
struct NowPlayingBar: View {
    let artworkURL: String
    let title: String
    let subtitle: String
    let isPlaying: Bool
    /// ボタンを押したとき（流れている曲を追いかけてスクロールし始める、など）
    var onControl: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: artworkURL, cornerRadius: 8).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                Text(verbatim: subtitle).font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
            }
            Spacer(minLength: 4)
            control("backward.fill", label: S("前の曲", "Previous")) {
                try await SystemMusicPlayer.shared.skipToPreviousEntry()
            }
            control(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? S("一時停止", "Pause") : S("再生", "Play")) {
                if isPlaying { SystemMusicPlayer.shared.pause() } else { try await SystemMusicPlayer.shared.play() }
            }
            control("forward.fill", label: S("次の曲", "Next")) {
                try await SystemMusicPlayer.shared.skipToNextEntry()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.dlCard)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func control(_ symbol: String, label: String, action: @escaping () async throws -> Void) -> some View {
        Button {
            onControl()
            Task { try? await action() }
        } label: {
            Image(systemName: symbol).frame(width: 36, height: 36)
        }
        .font(.title3)
        .foregroundColor(.dlPrimary)
        .accessibilityLabel(label)
    }
}

/// 「再生中」の印（動く波形）
struct NowPlayingBadge: View {
    var body: some View {
        Label(S("再生中", "Playing"), systemImage: "waveform")
            .symbolEffect(.variableColor.iterative)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.dlPrimary)
    }
}
