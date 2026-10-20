import Foundation
import SwiftData

/// スクリーンショット撮影用のサンプル（起動引数 -uiPreview のときだけ、メモリ上の DB に入れる）。
/// ジャケットは "sample:番号" で端末内に描く（実在の曲・ジャケットは使わない）。
@MainActor
enum SampleData {
    static func insert(into context: ModelContext) {
        let songs: [(String, String, String)] = [
            ("Morning Light", "Sora Kaze", "朝の光の中で聴きたくなった"),
            ("Blue Hour", "Nagi", "帰り道の空がきれいだった"),
            ("Lemonade Days", "The Citrus", ""),
            ("Night Drive", "Sora Kaze", "久しぶりに友だちと長電話"),
            ("Paper Planes", "Hana & Leo", ""),
            ("Slow Rain", "Nagi", "雨の日はこれ"),
            ("Sunny Side", "The Citrus", "テストが終わった！"),
            ("Starlight Avenue", "Hana & Leo", ""),
        ]
        let calendar = Calendar.current
        for offset in 0..<40 where offset % 9 != 5 {
            let day = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let pick = songs[(offset * 3) % songs.count]
            let index = (offset * 3) % songs.count
            let entry = SongEntry(dayKey: DayKey.string(from: day), song: PickedSong(
                id: "sample-\(offset)", title: pick.0, artist: pick.1, albumTitle: "Sample Album",
                artworkURL: "sample:\(index)", previewURL: nil, appleMusicURL: "https://music.apple.com/jp/"))
            entry.memo = offset == 0 ? "今日は朝から気分がよかったので、明るい曲にした。" : pick.2
            context.insert(entry)
        }
        try? context.save()
    }
}
