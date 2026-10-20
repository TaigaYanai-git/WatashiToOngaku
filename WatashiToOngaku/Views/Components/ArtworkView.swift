import SwiftUI

/// アルバムジャケット。スクリーンショット用のサンプル（"sample:番号"）は端末内で描く。
struct ArtworkView: View {
    let url: String
    var cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if url.hasPrefix("sample:"), let n = Int(url.dropFirst(7)) {
                SampleArtwork(index: n)
            } else {
                AsyncImage(url: URL(string: url)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Color.dlPrimaryBg
                        Image(systemName: "music.note").foregroundColor(.dlPrimary)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct SampleArtwork: View {
    let index: Int
    private static let palettes: [[Color]] = [
        [Color(red: 0.98, green: 0.62, blue: 0.55), Color(red: 0.55, green: 0.36, blue: 0.86)],
        [Color(red: 0.36, green: 0.78, blue: 0.86), Color(red: 0.20, green: 0.32, blue: 0.70)],
        [Color(red: 0.99, green: 0.84, blue: 0.40), Color(red: 0.94, green: 0.45, blue: 0.48)],
        [Color(red: 0.55, green: 0.86, blue: 0.62), Color(red: 0.18, green: 0.52, blue: 0.56)],
        [Color(red: 0.90, green: 0.60, blue: 0.86), Color(red: 0.36, green: 0.30, blue: 0.62)],
        [Color(red: 0.30, green: 0.30, blue: 0.36), Color(red: 0.70, green: 0.70, blue: 0.78)],
    ]

    var body: some View {
        let colors = Self.palettes[index % Self.palettes.count]
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: geo.size.width * 0.9)
                    .offset(x: geo.size.width * (index.isMultiple(of: 2) ? 0.3 : -0.3), y: geo.size.height * 0.3)
                Image(systemName: ["music.note", "music.quarternote.3", "waveform", "headphones", "guitars", "pianokeys"][index % 6])
                    .font(.system(size: geo.size.width * 0.32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

/// V-Diary と同じカードの見た目
struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.dlCard)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func dlCard(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

/// 試聴の再生／停止ボタンを重ねたジャケット
struct PlayableArtwork: View {
    let id: String
    let artworkURL: String
    let previewURL: String?
    /// nil なら横幅いっぱいの正方形
    var size: CGFloat?
    var cornerRadius: CGFloat = 16
    @ObservedObject private var player = PreviewPlayer.shared

    var body: some View {
        let playing = player.playingID == id
        let buttonSize = size.map { max(22, $0 * 0.16) } ?? 48
        ArtworkView(url: artworkURL, cornerRadius: cornerRadius)
            .frame(width: size, height: size)
            .frame(maxWidth: size == nil ? .infinity : nil)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                if previewURL != nil {
                    Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: buttonSize))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.45))
                        .padding(buttonSize * 0.3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { player.toggle(id: id, url: previewURL.flatMap(URL.init(string:))) }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(playing ? S("試聴を止める", "Stop preview") : S("試聴する", "Play preview"))
    }
}

extension Date {
    /// 2026年10月21日(水) / Wed, Oct 21, 2026
    var longDayText: String {
        formatted(.dateTime.locale(Locale(identifier: ThemeStore.shared.language == "en" ? "en_US" : "ja_JP"))
            .year().month().day().weekday(.abbreviated))
    }
}
