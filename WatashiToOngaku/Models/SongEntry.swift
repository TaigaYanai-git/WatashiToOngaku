import Foundation
import SwiftData

/// その日に選んだ一曲。1日に1件（dayKey で一意）。
@Model
final class SongEntry {
    var id: UUID = UUID()
    /// "yyyy-MM-dd"
    @Attribute(.unique) var dayKey: String = ""
    /// Apple Music のカタログ ID（MusicItemID.rawValue）
    var songID: String = ""
    var title: String = ""
    var artist: String = ""
    var albumTitle: String = ""
    var artworkURL: String = ""
    /// 約30秒の試聴用 URL
    var previewURL: String?
    /// Apple Music で開く URL
    var appleMusicURL: String?
    /// ひとことメモ
    var memo: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(dayKey: String, song: PickedSong) {
        self.dayKey = dayKey
        apply(song)
    }

    func apply(_ song: PickedSong) {
        songID = song.id
        title = song.title
        artist = song.artist
        albumTitle = song.albumTitle
        artworkURL = song.artworkURL
        previewURL = song.previewURL
        appleMusicURL = song.appleMusicURL
        updatedAt = Date()
    }

    var day: Date { DayKey.date(from: dayKey) ?? createdAt }
}

/// 検索結果から選んだ曲（MusicKit の型に依存しない形で受け渡す）
struct PickedSong: Equatable {
    let id: String
    let title: String
    let artist: String
    let albumTitle: String
    let artworkURL: String
    let previewURL: String?
    let appleMusicURL: String?
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from key: String) -> Date? { formatter.date(from: key) }
}
