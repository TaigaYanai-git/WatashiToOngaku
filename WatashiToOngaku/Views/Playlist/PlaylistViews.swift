import MusicKit
import SwiftUI

/// 「Apple Musicで再生」「ライブラリに保存」のボタン
struct PlaylistActions: View {
    /// 曲のカタログ ID（再生する順）
    let songIDs: [String]
    let name: String
    let description: String
    /// 同じ期間のプレイリストを作り直さず、入れ替えるための名前
    let key: String

    @State private var working: String?
    @State private var message: String?
    @State private var showOffer = false
    @State private var savedName: String?
    @AppStorage("playlist_shuffle") private var shuffle = false

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $shuffle) {
                Label(S("順番に再生", "In Order"), systemImage: "list.number").tag(false)
                Label(S("シャッフル", "Shuffle"), systemImage: "shuffle").tag(true)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 10) {
                button(shuffle ? "shuffle" : "play.fill", S("Apple Musicで再生", "Play in Apple Music"), id: "play") {
                    try await AppleMusicService.play(songIDs, shuffle: shuffle)
                }
                button("plus.square.on.square", S("ライブラリに保存", "Save to Library"), id: "save") {
                    try await AppleMusicService.save(songIDs, name: name, description: description, key: key)
                    savedName = name
                }
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

    private func button(_ symbol: String, _ title: String, id: String, action: @escaping () async throws -> Void) -> some View {
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
                if working == id { ProgressView().tint(.white) } else { Image(systemName: symbol) }
                Text(verbatim: title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(id == "play" ? .white : .dlPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(id == "play" ? AnyShapeStyle(LinearGradient.dlPrimary) : AnyShapeStyle(Color.dlPrimaryBg))
            .cornerRadius(14)
        }
        .disabled(working != nil)
    }
}
