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
    /// カスタムカラー（Plus）。accentIndex が customIndex のときに使う
    @Published var customColorHex: String {
        didSet { UserDefaults.standard.set(customColorHex, forKey: "dl_customColor") }
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
        // 後から足した色は、保存済みの番号がずれないよう最後に足す（表示の順番は displayAccents で決める）
        ThemeAccent(id: 9, name: "ピンク",
                    primary:    Color(red: 0.957, green: 0.420, blue: 0.718),
                    primaryEnd: Color(red: 0.980, green: 0.635, blue: 0.835),
                    primaryBg:  Color(red: 0.996, green: 0.902, blue: 0.953)),
    ]

    /// 設定に並べる順番（ピンクはローズの隣）
    static var displayAccents: [ThemeAccent] {
        [0, 1, 2, 9, 3, 4, 5, 6, 7, 8].map { accents[$0] }
    }

    /// accentIndex がこの値なら、カスタムカラー
    static var customIndex: Int { accents.count }
    var isCustom: Bool { accentIndex == Self.customIndex }

    var customColor: UIColor { UIColor(hex: customColorHex) ?? UIColor(red: 0.2, green: 0.6, blue: 0.6, alpha: 1) }

    var primary:    Color { isCustom ? Color(customColor) : Self.accents[accentIndex].primary }
    var primaryEnd: Color { isCustom ? Color(customColor.mixed(with: .white, 0.35)) : Self.accents[accentIndex].primaryEnd }
    var primaryBg:  Color { isCustom ? Color(customColor.mixed(with: .white, 0.86)) : Self.accents[accentIndex].primaryBg }

    var bgPattern: BgPattern { BgPattern(rawValue: bgPatternIndex) ?? .none }

    private init() {
        let ud = UserDefaults.standard
        // Default: ブラック (index 0); existing saved value respected
        // ピンクを足す前はカスタムカラーが 9 だったので、カスタムを選んでいた人は新しい番号にする
        var savedAccent = ud.integer(forKey: "dl_themeAccent")
        if ud.integer(forKey: "dl_themeAccentVersion") < 2 {
            if savedAccent == 9 { savedAccent = Self.customIndex }
            ud.set(2, forKey: "dl_themeAccentVersion")
        }
        accentIndex = min(savedAccent, Self.customIndex)
        customColorHex = ud.string(forKey: "dl_customColor") ?? "#33999A"
        isDark = ud.bool(forKey: "dl_themeIsDark")
        // Default: 水玉 (1) for first launch; 0 only when explicitly saved
        bgPatternIndex = ud.object(forKey: "dl_bgPattern") != nil
            ? ud.integer(forKey: "dl_bgPattern")
            : BgPattern.dots.rawValue
        if let saved = UserDefaults.standard.string(forKey: "dl_language") {
            language = saved
        } else {
            let sys = Locale.preferredLanguages.first ?? "ja"
            language = sys.hasPrefix("en") ? "en" : "ja"
        }
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
    }
}

extension UIColor {
    /// "#RRGGBB"
    convenience init?(hex: String) {
        let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    /// other を amount（0〜1）の割合で混ぜた色
    func mixed(with other: UIColor, _ amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}
