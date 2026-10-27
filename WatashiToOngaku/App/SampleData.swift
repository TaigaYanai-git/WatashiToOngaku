import Foundation
import SwiftData

/// スクリーンショット撮影用のサンプル（起動引数 -uiPreview のときだけ、メモリ上の DB に入れる）。
/// ジャケットは "sample:番号" で端末内に描く（実在の曲・ジャケットは使わない）。
@MainActor
enum SampleData {
    static func insert(into context: ModelContext) {
        let songs: [(String, String, String)] = [
            ("Morning Light", "Sora Kaze", S("朝の光の中で聴きたくなった", "Wanted this in the morning light", "아침 햇살 속에서 듣고 싶어졌다")),
            ("Blue Hour", "Nagi", S("帰り道の空がきれいだった", "The sky on the way home was beautiful", "집에 오는 길의 하늘이 예뻤다")),
            ("Lemonade Days", "The Citrus", ""),
            ("Night Drive", "Sora Kaze", S("久しぶりに友だちと長電話", "A long call with an old friend", "오랜만에 친구와 긴 통화")),
            ("Paper Planes", "Hana & Leo", ""),
            ("Slow Rain", "Nagi", S("雨の日はこれ", "My rainy day song", "비 오는 날엔 이 곡")),
            ("Sunny Side", "The Citrus", S("テストが終わった！", "Exams are over!", "시험이 끝났다!")),
            ("Starlight Avenue", "Hana & Leo", ""),
        ]
        let calendar = Calendar.current
        // -emptyToday のときは今日を空にする（未選択の画面の確認用）
        let first = ProcessInfo.processInfo.arguments.contains("-emptyToday") ? 1 : 0
        for offset in first..<40 where offset % 9 != 5 {
            let day = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let pick = songs[(offset * 3) % songs.count]
            let index = (offset * 3) % songs.count
            let entry = SongEntry(dayKey: DayKey.string(from: day), song: PickedSong(
                id: "sample-\(offset)", title: pick.0, artist: pick.1, albumTitle: "Sample Album",
                artworkURL: "sample:\(index)", previewURL: nil, appleMusicURL: "https://music.apple.com/jp/"))
            entry.memo = offset == 0 ? S("今日は朝から気分がよかったので、明るい曲にした。", "I felt great all morning, so I picked something bright.", "아침부터 기분이 좋아서 밝은 곡으로 골랐다.") : pick.2
            // 投稿した時刻はその日の朝〜夜に散らす（「◯秒前」にならないように）
            let hour = offset == 0 ? -1 : 8 + (offset * 5) % 13
            entry.createdAt = calendar.date(byAdding: .hour, value: hour, to: calendar.startOfDay(for: offset == 0 ? Date() : day)) ?? day
            if offset == 0 { entry.createdAt = Date().addingTimeInterval(-60 * 47) }
            context.insert(entry)
        }
        try? context.save()
        SocialStore.shared.loadPreview(entries: (try? context.fetch(FetchDescriptor<SongEntry>())) ?? [])
    }
}
