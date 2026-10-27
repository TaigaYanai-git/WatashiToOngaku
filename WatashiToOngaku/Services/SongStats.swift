import Foundation

/// 連続記録やアーティストのランキングなど、ふりかえり用の集計
enum SongStats {
    /// 今日（今日まだなら昨日）から遡って何日続けて記録しているか
    static func currentStreak(_ entries: [SongEntry], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let keys = Set(entries.map(\.dayKey))
        var day = calendar.startOfDay(for: today)
        if !keys.contains(DayKey.string(from: day)) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while keys.contains(DayKey.string(from: day)) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    static func bestStreak(_ entries: [SongEntry], calendar: Calendar = .current) -> Int {
        let days = Set(entries.compactMap { DayKey.date(from: $0.dayKey) }.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    struct ArtistCount: Identifiable {
        let artist: String
        let count: Int
        let artworkURL: String
        var id: String { artist }
    }

    /// よく選んだアーティスト（同数なら最近選んだ順）
    static func topArtists(_ entries: [SongEntry], limit: Int = 5) -> [ArtistCount] {
        Dictionary(grouping: entries, by: \.artistKey)
            .map { _, items in
                // 表記が違う曲が混ざっていたら、最近選んだ曲の表記で出す
                let latest = items.max { $0.dayKey < $1.dayKey }
                return (ArtistCount(artist: latest?.artist ?? "", count: items.count, artworkURL: latest?.artworkURL ?? ""),
                        latest?.dayKey ?? "")
            }
            .sorted { ($0.0.count, $0.1) > ($1.0.count, $1.1) }
            .prefix(limit)
            .map(\.0)
    }
}
