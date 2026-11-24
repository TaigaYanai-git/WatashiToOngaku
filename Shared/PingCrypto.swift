import CryptoKit
import Foundation

/// 通知の合図（Ping）に入れる名前の暗号化と、通知拡張（NotificationService）との受け渡し。
/// Ping は tag の索引で誰でも一覧できるので、名前はフレンドの鍵で閉じた暗号文だけを置く。
/// 通知が届いたら、端末の通知拡張がここに保存した鍵で開いて「〇〇さんが…」に書き換える。
enum PingCrypto {
    static let appGroup = "group.com.taigayanai.watashitoongaku"
    /// 暗号文の頭に付ける印（平文の名前と区別する）
    static let prefix = "e1:"
    private static let routesKey = "pingRoutes"

    /// 鍵（secret）から、名前を閉じるための鍵を作る。tag とは別の用途の文字列で作るので、tag から鍵は分からない
    static func nameKey(secret: String) -> SymmetricKey {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("OurMusic-ping-name".utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return SymmetricKey(data: Data(mac))
    }

    static func seal(_ name: String, secret: String) -> String? {
        guard !name.isEmpty, let box = try? AES.GCM.seal(Data(name.utf8), using: nameKey(secret: secret)).combined else { return nil }
        return prefix + box.base64EncodedString()
    }

    static func open(_ text: String, keyData: Data) -> String? {
        guard text.hasPrefix(prefix), let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: keyData)),
              let name = String(data: plain, encoding: .utf8) else { return nil }
        // 通知の1行に収める（改行を消し、長すぎる名前は切る）
        let oneLine = name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return oneLine.isEmpty ? nil : String(oneLine.prefix(40))
    }

    /// tag ごとの「名前を開く鍵」と「通知の文の型（%@ に名前が入る）」
    struct Route: Codable, Equatable {
        var key: Data
        var format: String
    }

    static func saveRoutes(_ routes: [String: Route]) {
        let defaults = UserDefaults(suiteName: appGroup)
        if routes.isEmpty {
            defaults?.removeObject(forKey: routesKey)
        } else if let data = try? JSONEncoder().encode(routes) {
            defaults?.set(data, forKey: routesKey)
        }
    }

    static func route(for tag: String) -> Route? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: routesKey),
              let routes = try? JSONDecoder().decode([String: Route].self, from: data) else { return nil }
        return routes[tag]
    }

    static func makeRoute(secret: String, format: String) -> Route {
        Route(key: nameKey(secret: secret).withUnsafeBytes { Data($0) }, format: format)
    }

    /// 通知の中身（CloudKit のクエリ通知の追加フィールド）から、名前入りの文を作る。作れなければ nil
    static func body(tag: String?, sealedName: String?) -> String? {
        guard let tag, let sealedName, let route = route(for: tag),
              let name = open(sealedName, keyData: route.key) else { return nil }
        return String(format: route.format, name)
    }
}
