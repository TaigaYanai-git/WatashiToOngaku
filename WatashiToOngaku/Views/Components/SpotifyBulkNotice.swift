import SwiftUI

/// Spotify を選んでいる人が、まとめて再生・保存（Apple Music だけの機能）を押したときに出す説明。
/// 「Apple Music で再生」を選んだら、両方使っている人とみなして次からは出さない
struct SpotifyBulkRequest {
    static let skipKey = "bulk_apple_music_ok"

    let save: Bool
    let action: () -> Void

    /// 説明が要らなければそのまま実行し、要るなら pending に入れて説明を出す
    @MainActor
    static func run(save: Bool = false, pending: Binding<SpotifyBulkRequest?>, _ action: @escaping () -> Void) {
        if MusicApp.preferred == .spotify && !UserDefaults.standard.bool(forKey: skipKey) {
            pending.wrappedValue = SpotifyBulkRequest(save: save, action: action)
        } else {
            action()
        }
    }
}

private struct SpotifyBulkNotice: ViewModifier {
    @Binding var pending: SpotifyBulkRequest?

    func body(content: Content) -> some View {
        content.alert(Text(verbatim: pending?.save == true
                           ? S("Spotify には保存できません", "Can't save to Spotify", "Spotify에는 저장할 수 없습니다")
                           : S("Spotify ではまとめて再生できません", "Can't play all in Spotify", "Spotify에서는 한꺼번에 재생할 수 없습니다")),
                      isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                      presenting: pending) { request in
            Button(request.save ? S("Apple Music に保存", "Save to Apple Music", "Apple Music에 저장")
                                : S("Apple Music で再生", "Play in Apple Music", "Apple Music에서 재생")) {
                UserDefaults.standard.set(true, forKey: SpotifyBulkRequest.skipKey)
                request.action()
            }
            Button("OK", role: .cancel) {}
        } message: { _ in
            Text(verbatim: S("まとめて再生とプレイリストへの保存は Apple Music でだけ使えます。Spotify ではアプリから曲を続けて流せない仕組みのためです。Spotify では1曲ずつ開いて聴けます。",
                             "Playing all and saving playlists work only with Apple Music, because Spotify doesn't let apps queue several songs. You can still open each song in Spotify.",
                             "한꺼번에 재생과 플레이리스트 저장은 Apple Music에서만 가능합니다. Spotify는 앱에서 여러 곡을 이어서 재생할 수 없기 때문입니다. Spotify에서는 한 곡씩 열어 들을 수 있습니다."))
        }
    }
}

extension View {
    func spotifyBulkNotice(_ pending: Binding<SpotifyBulkRequest?>) -> some View {
        modifier(SpotifyBulkNotice(pending: pending))
    }
}
