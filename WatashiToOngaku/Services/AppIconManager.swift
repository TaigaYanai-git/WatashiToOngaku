import UIKit

/// テーマカラーに合わせてアプリアイコンを切り替える（設定でオンにしたときだけ）。
/// 切り替えるたびに iOS が「アイコンを変更しました」と表示する（アプリからは消せない）。
@MainActor
enum AppIconManager {
    static let followsThemeKey = "icon_followsTheme"

    /// ThemeStore.accents と同じ並び。ブラック（0）は標準のアイコン
    private static let names: [String?] = [nil, "AppIcon-White", "AppIcon-Rose", "AppIcon-Coral", "AppIcon-Sunset",
                                           "AppIcon-Lemon", "AppIcon-Mint", "AppIcon-Sky", "AppIcon-Lavender"]

    static var followsTheme: Bool { UserDefaults.standard.bool(forKey: followsThemeKey) }

    static func apply(accentIndex: Int) {
        let name = followsTheme ? names[min(max(accentIndex, 0), names.count - 1)] : nil
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name)
    }
}
