import Foundation

/// 誕生日（年齢ごとのプレイリストに使う）。この端末にだけ保存する
enum Birthday {
    /// UserDefaults のキー。値は 1970 年からの秒数（0 なら未登録）
    static let key = "profile_birthday"

    static func date(from stored: Double) -> Date? {
        stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    /// 今日の年齢
    static func age(birthday: Date, on day: Date = Date()) -> Int {
        Calendar.current.dateComponents([.year], from: birthday, to: day).year ?? 0
    }

    /// その年齢だった期間（誕生日から、次の誕生日の前日まで）
    static func range(age: Int, birthday: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .year, value: age, to: birthday) ?? birthday
        let next = calendar.date(byAdding: .year, value: age + 1, to: birthday) ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: next) ?? next
        return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
    }
}
