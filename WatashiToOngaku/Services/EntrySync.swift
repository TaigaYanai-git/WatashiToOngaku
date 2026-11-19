import Foundation
import SQLite3
import SwiftData

/// 記録の iCloud 同期の後始末。
/// 入れ直した直後に今日の曲を選んでから iCloud の控えが届くと、同じ日が2件になる。
/// そのときは、あとから変えたほうを残す（メモが片方にしかなければ、残すほうに移す）。
@MainActor
enum EntrySync {
    /// 1.0.1 までは dayKey に一意の制約があり、データベースに一意の索引が作られている。
    /// 制約を外しても Core Data は索引を残す（モデルの変更と見なさない）ので、iCloud から同じ日の記録が
    /// 届くと保存に失敗する。データベースを開く前に、その索引だけを外す
    nonisolated static func dropOldUniqueIndex(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db); return
        }
        defer { sqlite3_close(db) }
        let result = sqlite3_exec(db, "DROP INDEX IF EXISTS Z_SongEntry_UNIQUE_dayKey", nil, nil, nil)
        if result != SQLITE_OK { print("[EntrySync] 索引を外せませんでした: \(result)") }
    }

    static func mergeDuplicates(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<SongEntry>()) else { return }
        var merged = 0
        for (_, group) in Dictionary(grouping: all, by: \.dayKey) where group.count > 1 {
            let sorted = group.sorted { ($0.updatedAt, $0.createdAt) > ($1.updatedAt, $1.createdAt) }
            let keep = sorted[0]
            for extra in sorted.dropFirst() {
                if keep.memo.isEmpty && !extra.memo.isEmpty { keep.memo = extra.memo }
                if extra.createdAt < keep.createdAt { keep.createdAt = extra.createdAt }
                context.delete(extra)
                merged += 1
            }
        }
        guard merged > 0 else { return }
        try? context.save()
        print("[EntrySync] 同じ日の記録を \(merged) 件まとめました")
    }
}
