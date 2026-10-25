import UIKit

/// アプリ内のダークモードとテーマカラーに合わせて、ホーム画面のアイコンを切り替える。
/// ホーム画面のアイコンは iPhone 本体の外観にしか連動しないので、ライト固定・ダーク固定のアイコン
/// （scripts/make_icons.py で作る）を代替アイコンとして持ち、アプリの設定に合わせて選ぶ。
/// 切り替えるたびに iOS が「アイコンを変更しました」と表示する（アプリからは消せない）。
@MainActor
enum AppIconManager {
    static let followsThemeKey = "icon_followsTheme"

    /// ThemeStore.accents と同じ並び。ブラック（0）は標準のアイコン
    private static let themes = ["", "White", "Rose", "Coral", "Sunset", "Lemon", "Mint", "Sky", "Lavender"]

    /// テーマカラーのアイコンは Plus の特典
    static var followsTheme: Bool { UserDefaults.standard.bool(forKey: followsThemeKey) && PlusStore.shared.isPlus }

    static func iconName(accentIndex: Int, isDark: Bool) -> String? {
        let theme = followsTheme ? themes[min(max(accentIndex, 0), themes.count - 1)] : ""
        let base = theme.isEmpty ? "AppIcon" : "AppIcon-\(theme)"
        if isDark { return base + "-Dark" }
        return theme.isEmpty ? nil : base
    }

    static func apply(accentIndex: Int = ThemeStore.shared.accentIndex, isDark: Bool = ThemeStore.shared.isDark) {
        let name = iconName(accentIndex: accentIndex, isDark: isDark)
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
    }
}
