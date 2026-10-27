import Combine
import SwiftUI

// MARK: - Accent definition

struct ThemeAccent: Identifiable {
    let id: Int
    let name: String
    let primary: Color
    let primaryEnd: Color
    let primaryBg: Color
    var needsBorder: Bool = false
}

// MARK: - Background pattern

enum BgPattern: Int, CaseIterable {
    case none    = 0
    case dots    = 1
    case border  = 2  // horizontal stripes
    case borderV = 3  // vertical stripes
    case stars   = 4
    case hearts  = 5

    var label: String {
        switch self {
        case .none:    return "なし"
        case .dots:    return "水玉"
        case .border:  return "ボーダー"
        case .borderV: return "ボーダー（縦）"
        case .stars:   return "スター"
        case .hearts:  return "ハート"
        }
    }
    var labelEn: String {
        switch self {
        case .none:    return "None"
        case .dots:    return "Dots"
        case .border:  return "Border"
        case .borderV: return "V-Border"
        case .stars:   return "Stars"
        case .hearts:  return "Hearts"
        }
    }
    var labelKo: String {
        switch self {
        case .none:    return "없음"
        case .dots:    return "물방울"
        case .border:  return "줄무늬"
        case .borderV: return "세로 줄무늬"
        case .stars:   return "별"
        case .hearts:  return "하트"
        }
    }
}

// MARK: - ThemeStore

/// Single source of truth for app-wide accent colour, dark/light mode, and background pattern.
/// Persisted in UserDefaults; drives Color.dlPrimary / dlPrimaryEnd / dlPrimaryBg.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var accentIndex: Int {
        didSet { UserDefaults.standard.set(accentIndex, forKey: "dl_themeAccent") }
    }
    @Published var isDark: Bool {
        didSet { UserDefaults.standard.set(isDark, forKey: "dl_themeIsDark") }
    }
    @Published var bgPatternIndex: Int {
        didSet { UserDefaults.standard.set(bgPatternIndex, forKey: "dl_bgPattern") }
    }

    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "dl_language")
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
    }

    // MARK: Palette
    // Order: neutrals first (black→white), then warm→cool chromatic

    static let accents: [ThemeAccent] = [
        ThemeAccent(id: 0, name: "ブラック",
                    primary:    Color(red: 0.22, green: 0.22, blue: 0.25),
                    primaryEnd: Color(red: 0.40, green: 0.40, blue: 0.44),
                    primaryBg:  Color(red: 0.91, green: 0.91, blue: 0.93)),
        ThemeAccent(id: 1, name: "ホワイト",
                    primary:    Color(white: 0.72),
                    primaryEnd: Color(white: 0.86),
                    primaryBg:  Color(white: 0.96),
                    needsBorder: true),
        ThemeAccent(id: 2, name: "ローズ",
                    primary:    Color(red: 0.898, green: 0.451, blue: 0.600),
                    primaryEnd: Color(red: 0.957, green: 0.655, blue: 0.765),
                    primaryBg:  Color(red: 0.988, green: 0.894, blue: 0.925)),
        ThemeAccent(id: 3, name: "コーラル",
                    primary:    Color(red: 0.878, green: 0.482, blue: 0.482),
                    primaryEnd: Color(red: 0.949, green: 0.639, blue: 0.639),
                    primaryBg:  Color(red: 1.000, green: 0.922, blue: 0.933)),
        ThemeAccent(id: 4, name: "サンセット",
                    primary:    Color(red: 0.910, green: 0.537, blue: 0.353),
                    primaryEnd: Color(red: 0.957, green: 0.690, blue: 0.478),
                    primaryBg:  Color(red: 0.984, green: 0.914, blue: 0.906)),
        ThemeAccent(id: 5, name: "レモン",
                    primary:    Color(red: 0.871, green: 0.761, blue: 0.247),
                    primaryEnd: Color(red: 0.941, green: 0.867, blue: 0.529),
                    primaryBg:  Color(red: 0.996, green: 0.984, blue: 0.882)),
        ThemeAccent(id: 6, name: "ミント",
                    primary:    Color(red: 0.298, green: 0.686, blue: 0.510),
                    primaryEnd: Color(red: 0.502, green: 0.796, blue: 0.659),
                    primaryBg:  Color(red: 0.878, green: 0.949, blue: 0.933)),
        ThemeAccent(id: 7, name: "スカイ",
                    primary:    Color(red: 0.290, green: 0.565, blue: 0.812),
                    primaryEnd: Color(red: 0.510, green: 0.753, blue: 0.910),
                    primaryBg:  Color(red: 0.890, green: 0.949, blue: 0.992)),
        ThemeAccent(id: 8, name: "ラベンダー",
                    primary:    Color(red: 0.647, green: 0.482, blue: 0.878),
                    primaryEnd: Color(red: 0.800, green: 0.639, blue: 0.949),
                    primaryBg:  Color(red: 0.929, green: 0.882, blue: 0.984)),
    ]

    var primary:    Color { Self.accents[accentIndex].primary }
    var primaryEnd: Color { Self.accents[accentIndex].primaryEnd }
    var primaryBg:  Color { Self.accents[accentIndex].primaryBg }

    var bgPattern: BgPattern { BgPattern(rawValue: bgPatternIndex) ?? .none }

    private init() {
        let ud = UserDefaults.standard
        // Default: ブラック (index 0); existing saved value respected
        // 以前のカスタムカラー（9 以上）を選んでいた人はブラックに戻す
        let savedAccent = ud.integer(forKey: "dl_themeAccent")
        accentIndex = Self.accents.indices.contains(savedAccent) ? savedAccent : 0
        isDark = ud.bool(forKey: "dl_themeIsDark")
        // Default: 水玉 (1) for first launch; 0 only when explicitly saved
        bgPatternIndex = ud.object(forKey: "dl_bgPattern") != nil
            ? ud.integer(forKey: "dl_bgPattern")
            : BgPattern.dots.rawValue
        if let saved = UserDefaults.standard.string(forKey: "dl_language") {
            language = saved
        } else {
            let sys = Locale.preferredLanguages.first ?? "ja"
            language = sys.hasPrefix("en") ? "en" : sys.hasPrefix("ko") ? "ko" : "ja"
        }
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
    }
}
