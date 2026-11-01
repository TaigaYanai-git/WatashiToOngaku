import UIKit

/// アプリ内のダークモードとテーマカラーに合わせて、ホーム画面のアイコンを切り替える。
/// ホーム画面のアイコンは iPhone 本体の外観にしか連動しないので、ライト固定・ダーク固定のアイコン
/// （scripts/make_icons.py で作る）を代替アイコンとして持ち、アプリの設定に合わせて選ぶ。
/// 切り替えるたびに iOS が「アイコンを変更しました」と表示する（アプリからは消せない）。
@MainActor
enum AppIconManager {
    static let followsThemeKey = "icon_followsTheme"
    /// Plus：固定するアイコン（テーマカラーの番号。-1 なら固定しない）と、ダークのアイコンにするか
    static let fixedThemeKey = "icon_fixedTheme"
    static let fixedDarkKey = "icon_fixedDark"
    /// 固定をやめたあと、テーマやダークモードを変えるまで今のアイコンのままにする
    private static let holdKey = "icon_hold"

    /// ThemeStore.accents と同じ並び。ブラック（0）は標準のアイコン
    static let themes = ["", "White", "Rose", "Coral", "Sunset", "Lemon", "Mint", "Sky", "Lavender"]

    static var followsTheme: Bool { UserDefaults.standard.bool(forKey: followsThemeKey) }

    /// 固定しているアイコン（Plus のときだけ効く）
    static var fixed: (theme: Int, isDark: Bool)? {
        let ud = UserDefaults.standard
        guard PlusStore.shared.isPlus, ud.object(forKey: fixedThemeKey) != nil else { return nil }
        let theme = ud.integer(forKey: fixedThemeKey)
        return themes.indices.contains(theme) ? (theme, ud.bool(forKey: fixedDarkKey)) : nil
    }

    static func setFixed(theme: Int?, isDark: Bool) {
        let ud = UserDefaults.standard
        if let theme { ud.set(theme, forKey: fixedThemeKey) } else { ud.removeObject(forKey: fixedThemeKey) }
        ud.set(isDark, forKey: fixedDarkKey)
        // 固定をやめたときは、今のアイコンのままにする（次にテーマやダークモードを変えたときから合わせる）
        if theme != nil { apply() } else { ud.set(true, forKey: holdKey) }
    }

    /// テーマの番号とダークかどうかから、アイコンの名前（標準のアイコンなら nil）
    static func name(theme index: Int, isDark: Bool) -> String? {
        let theme = themes.indices.contains(index) ? themes[index] : ""
        let base = theme.isEmpty ? "AppIcon" : "AppIcon-\(theme)"
        if isDark { return base + "-Dark" }
        return theme.isEmpty ? nil : base
    }

    /// カスタムカラーのアイコンはないので、テーマに合わせるときも標準（ブラック）のアイコンになる
    static func iconName(accentIndex: Int, isDark: Bool) -> String? {
        if let fixed { return name(theme: fixed.theme, isDark: fixed.isDark) }
        return name(theme: followsTheme ? accentIndex : 0, isDark: isDark)
    }

    /// 起動時：アプリの設定とアイコンがずれていたら合わせる（固定をやめた直後のアイコンはそのまま）
    static func syncOnLaunch() {
        guard !UserDefaults.standard.bool(forKey: holdKey) else { return }
        apply()
    }

    static func apply(accentIndex: Int = ThemeStore.shared.accentIndex, isDark: Bool = ThemeStore.shared.isDark) {
        UserDefaults.standard.removeObject(forKey: holdKey)
        let name = iconName(accentIndex: accentIndex, isDark: isDark)
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
    }
}
