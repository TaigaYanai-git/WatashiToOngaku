import XCTest
@testable import WatashiToOngaku

final class SongStatsTests: XCTestCase {
    private let calendar = Calendar.current

    private func entry(_ daysAgo: Int, artist: String = "A", from today: Date) -> SongEntry {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        return SongEntry(dayKey: DayKey.string(from: day), song: PickedSong(
            id: "\(daysAgo)", title: "t", artist: artist, albumTitle: "", artworkURL: "", previewURL: nil, appleMusicURL: nil))
    }

    func testCurrentStreakCountsFromYesterdayWhenTodayIsEmpty() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9))!
        let entries = [1, 2, 3, 5].map { entry($0, from: today) }
        XCTAssertEqual(SongStats.currentStreak(entries, today: today), 3)
    }

    func testCurrentStreakIncludesToday() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9))!
        XCTAssertEqual(SongStats.currentStreak([0, 1].map { entry($0, from: today) }, today: today), 2)
        XCTAssertEqual(SongStats.currentStreak([2].map { entry($0, from: today) }, today: today), 0)
    }

    func testBestStreak() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        let entries = [0, 1, 4, 5, 6, 7, 10].map { entry($0, from: today) }
        XCTAssertEqual(SongStats.bestStreak(entries), 4)
    }

    func testTopArtists() {
        let today = Date()
        let entries = [entry(0, artist: "B", from: today), entry(1, artist: "A", from: today),
                       entry(2, artist: "A", from: today), entry(3, artist: "C", from: today)]
        let top = SongStats.topArtists(entries)
        XCTAssertEqual(top.map(\.artist), ["A", "B", "C"])
        XCTAssertEqual(top.first?.count, 2)
    }
}
