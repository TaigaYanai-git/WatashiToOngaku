import Foundation

/// 曲を開く音楽アプリ。Spotify を選んだ人には「Spotifyで聴く」を先に出す。
/// 曲の検索・試聴・プレイリストの再生は、これまでどおり Apple Music のカタログを使う
/// （Spotify の Web API は、個人開発のアプリには利用できる人数の上限があるため）
enum MusicApp: String, CaseIterable, Identifiable {
    case appleMusic, spotify
    var id: String { rawValue }

    static let storageKey = "music_app"

    static var preferred: MusicApp {
        MusicApp(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .appleMusic
    }

    var name: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    var listenLabel: String {
        switch self {
        case .appleMusic: return S("Apple Musicで聴く", "Open in Apple Music")
        case .spotify: return S("Spotifyで聴く", "Open in Spotify", "Spotify에서 듣기")
        }
    }
}

enum MusicLinks {
    private static var spotifyCache: [String: URL] = [:]

    /// Spotify でその曲を開く URL。
    /// Apple Music の URL があれば song.link（Odesli）で同じ曲の Spotify の URL を探し、見つからなければ曲名とアーティストで Spotify を検索する。
    /// open.spotify.com のリンクは、Spotify が入っていればアプリで開く
    @MainActor
    static func spotifyURL(title: String, artist: String, appleMusicURL: String?) async -> URL {
        let fallback = searchURL(title: title, artist: artist)
        guard let appleMusicURL, !appleMusicURL.isEmpty else { return fallback }
        if let cached = spotifyCache[appleMusicURL] { return cached }
        var components = URLComponents(string: "https://api.song.link/v1-alpha.1/links")!
        components.queryItems = [URLQueryItem(name: "url", value: appleMusicURL), URLQueryItem(name: "songIfSingle", value: "true")]
        guard let url = components.url else { return fallback }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONDecoder().decode(OdesliResponse.self, from: data),
              let link = json.linksByPlatform["spotify"]?.url, let found = URL(string: link) else { return fallback }
        spotifyCache[appleMusicURL] = found
        return found
    }

    static func searchURL(title: String, artist: String) -> URL {
        let query = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? ""
        return URL(string: "https://open.spotify.com/search/\(query)") ?? URL(string: "https://open.spotify.com")!
    }

    private struct OdesliResponse: Decodable {
        struct Link: Decodable { let url: String }
        let linksByPlatform: [String: Link]
    }
}
