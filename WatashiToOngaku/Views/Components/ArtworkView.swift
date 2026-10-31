import SwiftUI

/// アルバムジャケット。スクリーンショット用のサンプル（"sample:番号"）は端末内で描く。
/// 読み込んだ画像は ArtworkCache に置くので、今日の画面で見た曲はカレンダーやふりかえりでもすぐ出る
struct ArtworkView: View {
    let url: String
    var cornerRadius: CGFloat = 12
    @ObservedObject private var cache = ArtworkCache.shared
    @State private var loaded: UIImage?

    var body: some View {
        Group {
            if url.hasPrefix("sample:"), let n = Int(url.dropFirst(7)) {
                SampleArtwork(index: n)
            } else if let image = loaded ?? cache.cached(url) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.dlPrimaryBg
                    Image(systemName: "music.note").foregroundColor(.dlPrimary)
                }
                .task(id: "\(url)#\(cache.generation)") { loaded = await cache.load(url) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// ジャケット画像の読み込みと、アプリを開いているあいだの置き場所。
/// AsyncImage は覚えておかず、失敗するとそのままになるので、自分で読み込んで失敗したら少し待ってやり直す
@MainActor
final class ArtworkCache: ObservableObject {
    static let shared = ArtworkCache()

    /// 上げると、読み込めていないジャケットをもう一度読み込む
    @Published private(set) var generation = 0
    private let images = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]
    private var failed: Set<String> = []

    private init() { images.countLimit = 300 }

    func cached(_ url: String) -> UIImage? { images.object(forKey: url as NSString) }

    func load(_ url: String) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = loading[url] { return await task.value }
        guard let target = URL(string: url) else { return nil }
        let task = Task<UIImage?, Never> {
            for attempt in 0..<3 {
                if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt))) }
                if let (data, _) = try? await URLSession.shared.data(from: target), let image = UIImage(data: data) {
                    return image
                }
            }
            return nil
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image {
            images.setObject(image, forKey: url as NSString)
            failed.remove(url)
        } else {
            failed.insert(url)
        }
        return image
    }

    /// 引っ張って更新：読み込めなかったジャケットを読み込み直す
    func reload() async {
        let urls = failed
        await withTaskGroup(of: Void.self) { group in
            for url in urls { group.addTask { _ = await self.load(url) } }
        }
        generation += 1
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
    /// 流す範囲が選ばれていれば、Apple Music の契約者にはその30秒を流す
    var songID: String?
    var clipStart: Double?
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
            .onTapGesture {
                player.toggle(id: id, url: previewURL.flatMap(URL.init(string:)), songID: songID, clipStart: clipStart)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(playing ? S("試聴を止める", "Stop preview") : S("試聴する", "Play preview"))
    }
}

extension Date {
    /// 2026年10月21日(水) / Wed, Oct 21, 2026 / 2026년 10월 21일 (수)
    var longDayText: String {
        formatted(.dateTime.locale(.app)
            .year().month().day().weekday(.abbreviated))
    }
}

extension Locale {
    /// アプリで選んだ言語の Locale（iPhone の言語設定ではなく、アプリ内の設定に合わせて日付などを書く）
    static var app: Locale { Locale(identifier: S("ja_JP", "en_US", "ko_KR")) }
}
