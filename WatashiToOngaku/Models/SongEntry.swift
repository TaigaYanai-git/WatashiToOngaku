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
    /// Apple Music のアーティスト ID（主なアーティスト）。検索した言語によってアーティスト名の表記が
    /// 「ビートルズ」「The Beatles」のように変わるので、集計ではこれで同じアーティストをまとめる。
    /// 選んだあとに AppleMusicService.fillArtistIDs が埋める
    var artistID: String = ""
    var albumTitle: String = ""
    var artworkURL: String = ""
    /// 約30秒の試聴用 URL
    var previewURL: String?
    /// Apple Music で開く URL
    var appleMusicURL: String?
    /// 曲の長さ（秒）。0 なら未取得
    var duration: Double = 0
    /// 流す30秒の始まり（秒）。nil なら Apple の試聴区間
    var clipStart: Double?
    /// ひとことメモ
    var memo: String = ""
    /// フレンドに共有する（日ごとに選べる）
    var shareSong: Bool = true
    /// メモもフレンドに見せる
    var shareMemo: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(dayKey: String, song: PickedSong) {
        self.dayKey = dayKey
        apply(song)
    }

    func apply(_ song: PickedSong) {
        if songID != song.id { artistID = "" }
        songID = song.id
        title = song.title
        artist = song.artist
        albumTitle = song.albumTitle
        artworkURL = song.artworkURL
        previewURL = song.previewURL
        appleMusicURL = song.appleMusicURL
        duration = song.duration
        clipStart = song.clipStart
        updatedAt = Date()
    }

    var day: Date { DayKey.date(from: dayKey) ?? createdAt }

    /// 同じアーティストかどうかを見分ける値（ID がまだなければ名前）
    var artistKey: String { artistID.isEmpty ? artist : artistID }
}

/// 検索結果から選んだ曲（MusicKit の型に依存しない形で受け渡す）
struct PickedSong: Hashable {
    let id: String
    let title: String
    let artist: String
    let albumTitle: String
    let artworkURL: String
    let previewURL: String?
    let appleMusicURL: String?
    var duration: Double = 0
    /// 流す30秒の始まり（秒）。nil なら Apple の試聴区間
    var clipStart: Double?
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
