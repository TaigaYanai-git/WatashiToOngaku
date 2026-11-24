import CloudKit
import XCTest
@testable import WatashiToOngaku

final class PingCryptoTests: XCTestCase {
    func testSealAndOpenWithSameSecret() {
        let sealed = PingCrypto.seal("Mio", secret: "secret-A")
        XCTAssertNotNil(sealed)
        XCTAssertFalse(sealed!.contains("Mio"))
        let key = PingCrypto.makeRoute(secret: "secret-A", format: "%@").key
        XCTAssertEqual(PingCrypto.open(sealed!, keyData: key), "Mio")
    }

    func testOtherSecretCannotOpen() {
        let sealed = PingCrypto.seal("Mio", secret: "secret-A")!
        let other = PingCrypto.makeRoute(secret: "secret-B", format: "%@").key
        XCTAssertNil(PingCrypto.open(sealed, keyData: other))
    }

    func testPlainOrEmptyIsNotOpened() {
        let key = PingCrypto.makeRoute(secret: "secret-A", format: "%@").key
        XCTAssertNil(PingCrypto.open("Mio", keyData: key))
        XCTAssertNil(PingCrypto.seal("", secret: "secret-A"))
    }

    func testNameIsOneLineAndShort() {
        let sealed = PingCrypto.seal("A\nB" + String(repeating: "x", count: 100), secret: "s")!
        let key = PingCrypto.makeRoute(secret: "s", format: "%@").key
        let name = PingCrypto.open(sealed, keyData: key)!
        XCTAssertFalse(name.contains("\n"))
        XCTAssertEqual(name.count, 40)
    }

    func testBodyUsesRouteFormat() {
        PingCrypto.saveRoutes(["tag1": PingCrypto.makeRoute(secret: "s", format: "%@さんがいいねしました")])
        defer { PingCrypto.saveRoutes([:]) }
        let body = PingCrypto.body(tag: "tag1", sealedName: PingCrypto.seal("Ken", secret: "s"))
        XCTAssertEqual(body, "Kenさんがいいねしました")
        XCTAssertNil(PingCrypto.body(tag: "other", sealedName: PingCrypto.seal("Ken", secret: "s")))
    }

    /// CloudKit のクエリ通知の形（追加フィールドは "af"）から、通知拡張と同じ手順で名前入りの文が作れる
    func testQueryNotificationPayloadGivesNamedBody() {
        PingCrypto.saveRoutes(["tag9": PingCrypto.makeRoute(secret: "s9", format: "%@さんがコメントしました")])
        defer { PingCrypto.saveRoutes([:]) }
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["body": "フレンドがコメントしました"], "mutable-content": 1],
            "ck": ["ce": 2, "cid": "iCloud.com.taigayanai.watashitoongaku", "nid": UUID().uuidString,
                   "qry": ["dbs": 2, "fo": 1, "rid": "q-x", "sid": "om-comments", "zid": "_defaultZone", "zoid": "_defaultOwner",
                           "af": ["tag": "tag9", "nickname": PingCrypto.seal("Yui", secret: "s9")!]]],
        ]
        let note = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification
        XCTAssertNotNil(note)
        let body = PingCrypto.body(tag: note?.recordFields?["tag"] as? String, sealedName: note?.recordFields?["nickname"] as? String)
        XCTAssertEqual(body, "Yuiさんがコメントしました")
    }
}
