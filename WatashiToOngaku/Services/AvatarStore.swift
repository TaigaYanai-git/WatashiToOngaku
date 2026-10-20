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

/// 丸いアイコン。画像がなければ名前の頭文字
struct AvatarView: View {
    let code: String
    let version: Int
    let nickname: String
    var size: CGFloat = 36
    @ObservedObject private var store = AvatarStore.shared

    var body: some View {
        let _ = store.revision
        Group {
            if let image = store.image(code: code, version: version) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(nickname.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient.dlPrimary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
