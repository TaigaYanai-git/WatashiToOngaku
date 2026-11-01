import CloudKit
import SwiftUI
import UIKit

/// ユーザーのアイコン画像。タイムラインを重くしないように：
/// - 128px 四方の JPEG（10KB 前後）に縮めて、FriendCode レコードの "avatar"（CKAsset）に置く
/// - 版番号 "avatarVersion" だけをいつも取り、画像は版が変わったときだけダウンロードする
/// - ダウンロードした画像は端末のキャッシュに保存し、表示はメモリ上のキャッシュから
@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()
    static let pixelSize: CGFloat = 128

    /// 表示の更新用（画像が届いたら増える）
    @Published private(set) var revision = 0

    private let memory = NSCache<NSString, UIImage>()
    private var loading = Set<String>()
    private let folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("avatars")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func file(code: String, version: Int) -> URL { folder.appendingPathComponent("\(code)-\(version).jpg") }

    func image(code: String, version: Int) -> UIImage? {
        guard version > 0 else { return nil }
        let key = "\(code)-\(version)" as NSString
        if let cached = memory.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: file(code: code, version: version).path) else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    /// 端末に無い版だけダウンロードする
    func fetchIfNeeded(code: String, version: Int, in db: CKDatabase) {
        guard version > 0, image(code: code, version: version) == nil, !loading.contains(code) else { return }
        loading.insert(code)
        Task {
            defer { loading.remove(code) }
            guard let results = try? await db.records(for: [CKRecord.ID(recordName: code)], desiredKeys: ["avatar"]),
                  let record = try? results[CKRecord.ID(recordName: code)]?.get(),
                  let asset = record["avatar"] as? CKAsset, let source = asset.fileURL else { return }
            try? FileManager.default.removeItem(at: file(code: code, version: version))
            try? FileManager.default.copyItem(at: source, to: file(code: code, version: version))
            revision += 1
        }
    }

    /// 自分のアイコンを端末にも置いておく（アップロード直後から表示するため）
    func storeOwn(_ data: Data, code: String, version: Int) {
        try? data.write(to: file(code: code, version: version))
        revision += 1
    }

    /// 選んだ写真を中央で正方形に切り抜き、128px の JPEG にする
    static func thumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let target = CGSize(width: pixelSize, height: pixelSize)
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            let scale = pixelSize / side
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

/// 丸いアイコン。画像がなければ初期アイコン、開発者は開発者のアイコン
struct AvatarView: View {
    let code: String
    let version: Int
    let nickname: String
    var size: CGFloat = 36
    /// 開発者（公式アカウント）なら、写真ではなく開発者のアイコンにする
    var isDeveloper = false
    @ObservedObject private var store = AvatarStore.shared

    var body: some View {
        let _ = store.revision
        Group {
            if isDeveloper {
                DeveloperAvatar(size: size)
            } else if let image = store.image(code: code, version: version) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                DefaultAvatar(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

extension AvatarView {
    init(friend: Friend, size: CGFloat = 36) {
        self.init(code: friend.code, version: friend.avatarVersion, nickname: friend.nickname, size: size,
                  isDeveloper: friend.isOfficial || friend.isDeveloper)
    }
}

/// 開発者のアイコン：アプリアイコンと同じレコードを、ブラックとホワイトを除くテーマカラーの7枚、輪に重ねて並べる。
/// 大きさは黄金比 φ で決める：円の半径を r として、盤の半径も、並べる輪の半径も r/φ²
private struct DeveloperAvatar: View {
    let size: CGFloat
    private static let phi: CGFloat = (1 + sqrt(5)) / 2
    /// ローズ〜ラベンダー
    private static let colors = ThemeStore.accents.dropFirst(2).map(\.primary)

    var body: some View {
        let unit = size / 2 / (Self.phi * Self.phi)
        ZStack {
            // 初期アイコンと同じブラックの背景
            LinearGradient(colors: [ThemeStore.accents[0].primary, ThemeStore.accents[0].primaryEnd],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(Self.colors.indices, id: \.self) { index in
                // いちばん上から時計回りに並べる
                let angle = Double(index) / Double(Self.colors.count) * 2 * .pi - .pi / 2
                RecordDisc(color: Self.colors[index])
                    .frame(width: unit * 2, height: unit * 2)
                    .shadow(color: .black.opacity(0.25), radius: size * 0.015)
                    .offset(x: unit * cos(angle), y: unit * sin(angle))
            }
        }
    }
}

/// アプリアイコンのレコード1枚（scripts/make_icons.py と同じく、半径 360 の盤を基準にした溝・光・ラベル）
private struct RecordDisc: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let radius = size.width / 2
            let k = radius / 360
            let center = CGPoint(x: radius, y: radius)
            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            context.fill(circle(radius), with: .color(color))
            for groove in stride(from: 330.0, to: 153, by: -22) {
                context.stroke(circle(groove * k), with: .color(.white.opacity(0.07)), lineWidth: 3 * k)
            }
            // 左上と右下に光の筋
            for flip in [0.0, 180.0] {
                for (r, start, end) in [(280.0, -126.0, -166.0), (230.0, -123.0, -149.0)] {
                    var arc = Path()
                    arc.addArc(center: center, radius: r * k, startAngle: .degrees(start + flip),
                               endAngle: .degrees(end + flip), clockwise: true)
                    context.stroke(arc, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 18 * k, lineCap: .round))
                }
            }
            var label = circle(118 * k)
            label.addPath(circle(18 * k))
            context.fill(label, with: .color(.white), style: FillStyle(eoFill: true))
        }
    }
}

/// 写真を設定していないときの、人の形の初期アイコン。比率はすべて黄金比 φ で決める：
/// 頭の直径と頭の中心の高さは 1/φ²、体の上端は 1/φ、体の幅は頭の直径 × φ（＝ 1/φ）
private struct DefaultAvatar: View {
    let size: CGFloat
    private static let phi: CGFloat = (1 + sqrt(5)) / 2

    var body: some View {
        let phi = Self.phi
        let head = size / (phi * phi)
        let bodyWidth = head * phi
        ZStack(alignment: .top) {
            // テーマカラーに左右されず、ブラックのテーマと同じ色にする
            LinearGradient(colors: [ThemeStore.accents[0].primary, ThemeStore.accents[0].primaryEnd],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .frame(width: head, height: head)
                .offset(y: size / (phi * phi) - head / 2)
            Ellipse()
                .frame(width: bodyWidth, height: bodyWidth / phi * 2)
                .offset(y: size / phi)
        }
        .foregroundColor(.white.opacity(0.95))
    }
}
