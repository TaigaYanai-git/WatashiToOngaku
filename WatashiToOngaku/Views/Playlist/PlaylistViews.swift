import MusicKit
import SwiftUI

/// 「上から再生」「シャッフル」「ライブラリに保存」のボタン（Apple Music の契約が必要）
struct PlaylistActions: View {
    /// 曲のカタログ ID（一覧に並んでいる順。「上から再生」はこの順に流す）
    let songIDs: [String]
    /// ライブラリに保存するときの順（nil なら songIDs の順）
    var saveSongIDs: [String]?
    let name: String
    let description: String
    /// 同じ期間のプレイリストを作り直さず、入れ替えるための名前
    let key: String
    /// 流し始めたとき（流れている曲を追いかけてスクロールし始める、など）
    var onPlay: () -> Void = {}

    @State private var working: String?
    @State private var message: String?
    @State private var showOffer = false
    @State private var savedName: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                button(id: "order", title: S("上から再生", "Play"), primary: true) {
                    PlayFromTopIcon()
                } action: {
                    try await AppleMusicService.play(songIDs)
                    onPlay()
                }
                button(id: "shuffle", title: S("シャッフル", "Shuffle")) {
                    Image(systemName: "shuffle")
                } action: {
                    try await AppleMusicService.play(songIDs, shuffle: true)
                    onPlay()
                }
            }
            button(id: "save", title: S("ライブラリに保存", "Save to Library")) {
                Image(systemName: "plus.square.on.square")
            } action: {
                try await AppleMusicService.save(saveSongIDs ?? songIDs, name: name, description: description, key: key)
                savedName = name
            }
            if let savedName {
                Button {
                    AppleMusicService.openMusicApp()
                } label: {
                    Label(S("「\(savedName)」を保存しました。ミュージックで開く", "Saved \"\(savedName)\". Open Music"),
                          systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.dlPrimary)
                }
            }
        }
        .disabled(songIDs.isEmpty)
        .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .musicSubscriptionOffer(isPresented: $showOffer, options: MusicSubscriptionOffer.Options(messageIdentifier: .playMusic))
    }

    private func button<Icon: View>(id: String, title: String, primary: Bool = false, @ViewBuilder icon: () -> Icon,
                                    action: @escaping () async throws -> Void) -> some View {
        Button {
            working = id
            Task {
                defer { working = nil }
                do {
                    try await action()
                } catch AppleMusicService.Failure.noSubscription(let canSubscribe) where canSubscribe {
                    showOffer = true
                } catch {
                    message = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 6) {
                if working == id { ProgressView().tint(primary ? .white : .dlPrimary) } else { icon() }
                Text(verbatim: title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(primary ? .white : .dlPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary ? AnyShapeStyle(LinearGradient.dlPrimary) : AnyShapeStyle(Color.dlPrimaryBg))
            .cornerRadius(14)
        }
        .disabled(working != nil)
    }
}

/// 「上から再生」のアイコン：下向きの矢印の横に再生マーク
struct PlayFromTopIcon: View {
    var body: some View {
        HStack(spacing: 2) {
            // 矢印は縦に伸ばして長く、再生マークは小さめに
            Image(systemName: "arrow.down").fontWeight(.semibold).scaleEffect(x: 1, y: 1.35)
            Image(systemName: "play.fill").imageScale(.small)
        }
    }
}
