import XCTest
@testable import WatashiToOngaku

final class ReminderScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testIncludesTodayWhenTimeHasNotPassedAndNotRecorded() {
        let days = ReminderStore.reminderDays(now: date(22, 9), hour: 21, minute: 0,
                                              recordedDayKeys: [], days: 3, calendar: calendar)
        XCTAssertEqual(days.map(\.dayKey), ["2026-11-22", "2026-11-23", "2026-11-24"])
        XCTAssertEqual(days[0].date, date(22, 21))
    }

    func testSkipsTodayWhenRecorded() {
        let days = ReminderStore.reminderDays(now: date(22, 9), hour: 21, minute: 0,
                                              recordedDayKeys: ["2026-11-22"], days: 3, calendar: calendar)
        XCTAssertEqual(days.map(\.dayKey), ["2026-11-23", "2026-11-24"])
    }

    func testSkipsTodayWhenTimeHasPassed() {
        let days = ReminderStore.reminderDays(now: date(22, 21, 30), hour: 21, minute: 0,
                                              recordedDayKeys: [], days: 2, calendar: calendar)
        XCTAssertEqual(days.map(\.dayKey), ["2026-11-23"])
    }

    func testCrossesMonthEndAndStaysWithinNotificationLimit() {
        let days = ReminderStore.reminderDays(now: date(30, 8), hour: 7, minute: 30,
                                              recordedDayKeys: [], calendar: calendar)
        XCTAssertEqual(days.first?.dayKey, "2026-12-01")
        XCTAssertLessThanOrEqual(days.count, 64)
        XCTAssertEqual(days.first?.date, calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 7, minute: 30)))
    }
}
