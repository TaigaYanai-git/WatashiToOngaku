import UIKit

/// アプリ内のダークモードとテーマカラーに合わせて、ホーム画面のアイコンを切り替える。
/// ホーム画面のアイコンは iPhone 本体の外観にしか連動しないので、ライト固定・ダーク固定のアイコン
/// （scripts/make_icons.py で作る）を代替アイコンとして持ち、アプリの設定に合わせて選ぶ。
/// 切り替えるたびに iOS が「アイコンを変更しました」と表示する（アプリからは消せない）。
@MainActor
enum AppIconManager {
    static let followsThemeKey = "icon_followsTheme"

    /// ThemeStore.accents と同じ並び。ブラック（0）は標準のアイコン
    private static let themes = ["", "White", "Rose", "Coral", "Sunset", "Lemon", "Mint", "Sky", "Lavender", "Pink"]

    static var followsTheme: Bool { UserDefaults.standard.bool(forKey: followsThemeKey) }

    static func iconName(accentIndex: Int, isDark: Bool) -> String? {
        // カスタムカラーのアイコンは作れない（アイコンはアプリに入れておいたものしか使えない）ので、いちばん近い色のアイコンにする
        let index = accentIndex == ThemeStore.customIndex ? nearestAccent(to: ThemeStore.shared.customColor) : accentIndex
        let theme = followsTheme && themes.indices.contains(index) ? themes[index] : ""
        let base = theme.isEmpty ? "AppIcon" : "AppIcon-\(theme)"
        if isDark { return base + "-Dark" }
        return theme.isEmpty ? nil : base
    }

    /// いちばん近いテーマカラー。鮮やかな色は色合い（色相）がいちばん近い色、くすんだ色や暗い色はブラックかホワイト
    static func nearestAccent(to color: UIColor) -> Int {
        func hsb(_ color: UIColor) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            return (h, s, b)
        }
        let target = hsb(color)
        if target.s < 0.2 || target.b < 0.3 { return target.b < 0.55 ? 0 : 1 }
        // ブラック（0）・ホワイト（1）以外の、色のあるテーマから選ぶ
        let colorful = Array(2..<ThemeStore.accents.count)
        let distances = colorful.map { index -> CGFloat in
            let diff = abs(hsb(UIColor(ThemeStore.accents[index].primary)).h - target.h)
            return min(diff, 1 - diff)
        }
        return distances.indices.min { distances[$0] < distances[$1] }.map { colorful[$0] } ?? 0
    }

    static func apply(accentIndex: Int = ThemeStore.shared.accentIndex, isDark: Bool = ThemeStore.shared.isDark) {
        let name = iconName(accentIndex: accentIndex, isDark: isDark)
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
    }
}
