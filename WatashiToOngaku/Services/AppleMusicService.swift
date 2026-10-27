import MusicKit
import SwiftData
import UIKit

/// プレイリストを Apple Music で聴く：ミュージックアプリで続けて再生する、またはライブラリにプレイリストとして保存する。
/// どちらも Apple Music の契約が必要（検索と試聴は契約なしで使える）。
@MainActor
enum AppleMusicService {
    enum Failure: LocalizedError {
        case notAuthorized
        /// 契約していない。canSubscribe なら Apple Music の案内（無料トライアルなど）を出せる
        case noSubscription(canSubscribe: Bool)
        case noSongs

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return S("Apple Music へのアクセスが許可されていません。設定アプリで許可してください。",
                         "Apple Music access isn't allowed. Please enable it in Settings.")
            case .noSubscription:
                return S("Apple Music で聴くには、Apple Music の契約が必要です。",
                         "An Apple Music subscription is needed to listen in Apple Music.")
            case .noSongs:
                return S("Apple Music で見つかる曲がありませんでした。", "No songs were found in Apple Music.")
            }
        }
    }

    /// 許可と契約を確かめる
    private static func prepare() async throws {
        var status = MusicAuthorization.currentStatus
        if status == .notDetermined { status = await MusicAuthorization.request() }
        guard status == .authorized else { throw Failure.notAuthorized }
        let subscription = try await MusicSubscription.current
        guard subscription.canPlayCatalogContent else {
            throw Failure.noSubscription(canSubscribe: subscription.canBecomeSubscriber)
        }
    }

    /// カタログ ID から曲を取り出す（並びはそのまま、同じ曲は1回だけ）
    private static func songs(for ids: [String]) async throws -> [Song] {
        var seen = Set<String>()
        let unique = ids.filter { !$0.isEmpty && !$0.hasPrefix("sample") && seen.insert($0).inserted }
        var found: [MusicItemID: Song] = [:]
        for chunk in unique.chunked(100) {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
            for song in try await request.response().items { found[song.id] = song }
        }
        let songs = unique.compactMap { found[MusicItemID($0)] }
        guard !songs.isEmpty else { throw Failure.noSongs }
        return songs
    }

    /// ミュージックアプリで、並べた順に（shuffle ならランダムな順に）再生する
    static func play(_ ids: [String], shuffle: Bool = false) async throws {
        try await prepare()
        let songs = try await songs(for: ids)
        PreviewPlayer.shared.stop()
        let player = SystemMusicPlayer.shared
        player.queue = SystemMusicPlayer.Queue(for: shuffle ? songs.shuffled() : songs)
        player.state.shuffleMode = shuffle ? .songs : .off
        try await player.play()
    }

    /// ライブラリにプレイリストとして保存する。同じ期間を前にも保存していたら、そのプレイリストの曲を入れ替える
    static func save(_ ids: [String], name: String, description: String, key: String) async throws {
        try await prepare()
        let songs = try await songs(for: ids)
        let storeKey = "playlist_\(key)"
        if let saved = UserDefaults.standard.string(forKey: storeKey) {
            var request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.id, equalTo: MusicItemID(saved))
            if let playlist = try? await request.response().items.first {
                try await MusicLibrary.shared.edit(playlist, name: name, description: description, items: songs)
                return
            }
        }
        let playlist = try await MusicLibrary.shared.createPlaylist(
            name: name, description: description, authorDisplayName: S("Our Music", "Our Music"), items: songs)
        UserDefaults.standard.set(playlist.id.rawValue, forKey: storeKey)
    }

    /// アーティスト ID や正式名称がまだない記録に、Apple Music で調べた主なアーティストの ID と正式名称を入れる（契約は不要）
    static func fillArtistIDs(in context: ModelContext) async {
        guard MusicAuthorization.currentStatus == .authorized,
              let entries = try? context.fetch(FetchDescriptor<SongEntry>()) else { return }
        let missing = entries.filter {
            ($0.artistID.isEmpty || $0.artistName.isEmpty) && !$0.songID.isEmpty && !$0.songID.hasPrefix("sample")
        }
        guard !missing.isEmpty else { return }

        // 曲 → アーティスト ID
        var artistIDs: [String: String] = [:]
        let needIDs = Array(Set(missing.filter { $0.artistID.isEmpty }.map(\.songID)))
        for chunk in needIDs.chunked(100) {
            var request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
            request.properties = [.artists]
            guard let songs = try? await request.response().items else { continue }
            for song in songs {
                if let artist = song.artists?.first { artistIDs[song.id.rawValue] = artist.id.rawValue }
            }
        }
        for entry in missing where entry.artistID.isEmpty {
            if let id = artistIDs[entry.songID] { entry.artistID = id }
        }

        // アーティスト ID → 正式名称
        let needNames = Array(Set(missing.filter { $0.artistName.isEmpty && !$0.artistID.isEmpty }.map(\.artistID)))
        if !needNames.isEmpty, let storefront = try? await MusicDataRequest.currentCountryCode {
            let local = await artistNames(needNames, storefront: storefront, language: nil)
            let english = await artistNames(needNames, storefront: storefront, language: "en-US")
            for entry in missing where entry.artistName.isEmpty {
                guard let name = local[entry.artistID] ?? english[entry.artistID] else { continue }
                entry.artistName = officialName(local: name, english: english[entry.artistID])
            }
        }
        try? context.save()
    }

    /// アーティスト名をまとめて取り出す。language が nil ならストアの標準の言語
    private static func artistNames(_ ids: [String], storefront: String, language: String?) async -> [String: String] {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Attributes: Decodable { let name: String }
                let id: String
                let attributes: Attributes?
            }
            let data: [Item]
        }
        var names: [String: String] = [:]
        for chunk in ids.chunked(25) {
            var components = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(storefront)/artists")!
            components.queryItems = [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))]
            if let language { components.queryItems?.append(URLQueryItem(name: "l", value: language)) }
            guard let url = components.url,
                  let data = try? await MusicDataRequest(urlRequest: URLRequest(url: url)).response().data,
                  let response = try? JSONDecoder().decode(Response.self, from: data) else { continue }
            for item in response.data {
                if let name = item.attributes?.name { names[item.id] = name }
            }
        }
        return names
    }

    /// 日本や韓国のストアでは、海外のアーティストがカタカナやハングルで書かれている（ビートルズ）。
    /// その読みが英語名（The Beatles）と違えば海外のアーティストとみなして英語名を使う。
    /// 読みが英語名と同じ（ヨルシカ / Yorushika）なら、その国のアーティストなのでそのまま使う
    static func officialName(local: String, english: String?) -> String {
        guard let english, english != local, !english.isEmpty else { return local }
        let ignored = CharacterSet.whitespaces.union(.punctuationCharacters).union(.symbols)
            .union(CharacterSet(charactersIn: "ー・"))
        let letters = local.unicodeScalars.filter { !ignored.contains($0) }
        guard !letters.isEmpty, letters.allSatisfy({
            (0x30A0...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value)
        }) else { return local }
        func simplified(_ text: String) -> String {
            let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
            let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
            return String(plain.lowercased().unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) }.map(Character.init))
        }
        let reading = simplified(local), name = simplified(english)
        guard !reading.isEmpty, !name.isEmpty else { return local }
        let distance = editDistance(Array(reading), Array(name))
        return Double(distance) / Double(max(reading.count, name.count)) <= 0.3 ? local : english
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }

    /// ミュージックアプリを開く
    static func openMusicApp() {
        if let url = URL(string: "music://") { UIApplication.shared.open(url) }
    }
}
