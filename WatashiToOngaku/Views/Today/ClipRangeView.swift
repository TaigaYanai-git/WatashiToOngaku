import MusicKit
import SwiftUI

/// 曲を選ぶときに、流す30秒の範囲を選ぶ（MusicPickerSheet から開く）。
/// 曲の好きな位置から流すには Apple Music の契約が必要（契約していない人には Apple の試聴区間が流れる）
struct ClipRangeView: View {
    let song: PickedSong
    let onDone: (PickedSong) -> Void

    @ObservedObject private var player = PreviewPlayer.shared
    @State private var duration: Double
    @State private var start: Double
    @State private var useApplePreview: Bool
    @State private var canPlayFull: Bool?
    @State private var canSubscribe = false
    @State private var showOffer = false

    private static let auditionID = "clip-audition"

    init(song: PickedSong, onDone: @escaping (PickedSong) -> Void) {
        self.song = song
        self.onDone = onDone
        _duration = State(initialValue: song.duration)
        _start = State(initialValue: song.clipStart ?? 0)
        _useApplePreview = State(initialValue: song.clipStart == nil)
    }

    private var maxStart: Double { max(0, duration - PreviewPlayer.clipLength) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    ArtworkView(url: song.artworkURL, cornerRadius: 12).frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title).font(.headline).foregroundColor(.dlText).lineLimit(2)
                        Text(song.artist).font(.subheadline).foregroundColor(.dlTextSub).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .dlCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: S("流す30秒", "The 30 Seconds to Play"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.dlText)
                    Picker("", selection: $useApplePreview) {
                        Text(verbatim: S("Apple の試聴区間", "Apple Preview")).tag(true)
                        Text(verbatim: S("好きな30秒", "Choose 30 sec")).tag(false)
                    }
                    .pickerStyle(.segmented)

                    if useApplePreview {
                        Text(verbatim: S("Apple Music が用意した試聴用の約30秒を流します。",
                                         "Plays the ~30 second preview chosen by Apple Music."))
                            .font(.caption).foregroundColor(.dlTextSub)
                    } else if duration <= 0 {
                        ProgressView().tint(.dlPrimary).frame(maxWidth: .infinity)
                    } else {
                        rangePicker
                    }
                }
                .dlCard()

                if canPlayFull == false && !useApplePreview {
                    subscriptionNote
                }

                Button(S("この曲にする", "Choose This Song")) {
                    player.stop()
                    var picked = song
                    picked.duration = duration
                    picked.clipStart = useApplePreview ? nil : min(start, maxStart)
                    onDone(picked)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!useApplePreview && duration <= 0)
            }
            .padding(20)
        }
        .background(DlBackground().ignoresSafeArea())
        .navigationTitle(Text(verbatim: S("流す30秒を選ぶ", "Choose the 30 Seconds")))
        .navigationBarTitleDisplayMode(.inline)
        .appNavBarBackground()
        .musicSubscriptionOffer(isPresented: $showOffer, options: MusicSubscriptionOffer.Options(messageIdentifier: .playMusic))
        .task { await load() }
        .onDisappear { player.stop() }
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: "\(Self.time(start)) – \(Self.time(min(start + PreviewPlayer.clipLength, duration)))")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundColor(.dlText)
                Spacer()
                Text(verbatim: S("全体 \(Self.time(duration))", "of \(Self.time(duration))", "전체 \(Self.time(duration))"))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.dlTextSub)
            }
            // 曲全体の中の30秒の位置
            GeometryReader { geo in
                let width = geo.size.width
                let windowWidth = max(12, width * PreviewPlayer.clipLength / max(duration, PreviewPlayer.clipLength))
                let x = maxStart > 0 ? (width - windowWidth) * start / maxStart : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dlPrimaryBg)
                    Capsule().fill(LinearGradient.dlPrimary).frame(width: windowWidth).offset(x: x)
                }
            }
            .frame(height: 14)
            Slider(value: $start, in: 0...max(maxStart, 1), step: 1) { editing in
                // 指を離したら、その位置から試聴する
                if !editing, canPlayFull == true { audition() }
            }
            .tint(.dlPrimary)
            .disabled(maxStart <= 0)
            Button {
                if player.playingID == Self.auditionID { player.stop() } else { audition() }
            } label: {
                Label(player.playingID == Self.auditionID ? S("止める", "Stop") : S("この30秒を聴く", "Play These 30 Seconds"),
                      systemImage: player.playingID == Self.auditionID ? "stop.fill" : "play.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(canPlayFull != true)
        }
    }

    private var subscriptionNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(S("好きな位置から流すには Apple Music の契約が必要です", "An Apple Music subscription is needed to play from any point"),
                  systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlText)
            Text(verbatim: S("範囲は選んで保存できます。契約しているフレンドには選んだ30秒が、契約していない人には Apple の試聴区間が流れます。",
                             "You can still save a range. Friends with Apple Music hear your 30 seconds; others hear Apple's preview."))
                .font(.caption)
                .foregroundColor(.dlTextSub)
            if canSubscribe {
                Button(S("Apple Music について見る", "Learn About Apple Music")) { showOffer = true }
                    .font(.subheadline)
                    .foregroundColor(.dlPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
    }

    private func audition() {
        player.play(id: Self.auditionID, url: song.previewURL.flatMap(URL.init(string:)),
                    songID: song.id, clipStart: min(start, maxStart))
    }

    /// 曲の長さと契約を調べる
    private func load() async {
        if MusicAuthorization.currentStatus == .notDetermined { _ = await MusicAuthorization.request() }
        if let subscription = try? await MusicSubscription.current {
            canPlayFull = subscription.canPlayCatalogContent
            canSubscribe = subscription.canBecomeSubscriber
        } else {
            canPlayFull = false
        }
        if duration <= 0, !song.id.hasPrefix("sample") {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(song.id))
            duration = (try? await request.response().items.first?.duration) ?? 0
        }
        if song.id.hasPrefix("sample") { duration = 200 }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
