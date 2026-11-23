import XCTest
@testable import WatashiToOngaku

@MainActor
final class SocialConnectionsTests: XCTestCase {
    func testDayKeyOfComment() {
        XCTAssertEqual(SocialStore.dayKey(ofComment: "c-s-ABCDEFGHJKLMNPQRSTUVWXYZ-2026-11-23-0"), "2026-11-23")
        XCTAssertEqual(SocialStore.dayKey(ofComment: "c-s-ABCDEFGHJKLMNPQRSTUVWXYZ-2025-01-05-12"), "2025-01-05")
        XCTAssertNil(SocialStore.dayKey(ofComment: "c-x"))
    }

    func testPingTagIsStableAndSeparatesKinds() {
        let post = SocialStore.pingTag(secret: "SECRET", kind: "post")
        XCTAssertEqual(post, SocialStore.pingTag(secret: "SECRET", kind: "post"))
        XCTAssertEqual(post.count, 32)
        XCTAssertNotEqual(post, SocialStore.pingTag(secret: "SECRET", kind: "comment"))
        XCTAssertNotEqual(post, SocialStore.pingTag(secret: "OTHER", kind: "post"))
        // 目印に鍵がそのまま出ない
        XCTAssertFalse(post.contains("SECRET"))
    }

    func testSpotifySearchURLEncodesQuery() {
        let url = MusicLinks.searchURL(title: "夜に駆ける", artist: "YOASOBI/Ayase?")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://open.spotify.com/search/"))
        // アーティスト名の "/" や "?" がパスやクエリを壊さない
        XCTAssertFalse(url.absoluteString.dropFirst("https://open.spotify.com/search/".count).contains("/"))
        XCTAssertNil(url.query)
    }
}
