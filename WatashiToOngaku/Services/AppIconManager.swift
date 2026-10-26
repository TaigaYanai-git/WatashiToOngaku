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

    static var followsTheme: Bool { UserDefaults.standard.bool(forKey: followsThemeKey) }

    static func iconName(accentIndex: Int, isDark: Bool) -> String? {
        let theme = followsTheme && themes.indices.contains(accentIndex) ? themes[accentIndex] : ""
        let base = theme.isEmpty ? "AppIcon" : "AppIcon-\(theme)"
        if isDark { return base + "-Dark" }
        return theme.isEmpty ? nil : base
    }

    /// 切り替えの途中か。iOS は前の切り替え（とお知らせ）が終わる前に次を頼むと断るので、1つずつ順番に行う
    private static var isChanging = false
    private static var needsChange = false
    private static var retries = 0
    private static var activeObserver: NSObjectProtocol?

    /// 今のテーマカラー・ダークモードに合うアイコンにする。
    /// 何度呼んでも、切り替えが終わってから最新の設定で1回ずつ行う
    static func apply() {
        needsChange = true
        run()
    }

    private static func run() {
        guard needsChange, !isChanging, UIApplication.shared.supportsAlternateIcons else { return }
        // アプリが前に出ていないと切り替えられないので、前に出たときにやり直す
        guard UIApplication.shared.applicationState == .active else {
            if activeObserver == nil {
                activeObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { _ in
                    Task { @MainActor in
                        if let observer = activeObserver { NotificationCenter.default.removeObserver(observer) }
                        activeObserver = nil
                        run()
                    }
                }
            }
            return
        }
        let theme = ThemeStore.shared
        let name = iconName(accentIndex: theme.accentIndex, isDark: theme.isDark)
        needsChange = false
        guard UIApplication.shared.alternateIconName != name else { return }
        isChanging = true
        UIApplication.shared.setAlternateIconName(name) { error in
            Task { @MainActor in
                isChanging = false
                if let error {
                    // 前のお知らせの処理中などで断られたら、少し待ってやり直す
                    print("[AppIcon] \(name ?? "default") に切り替えられませんでした: \(error)")
                    retries += 1
                    guard retries <= 5 else { retries = 0; return }
                    needsChange = true
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                } else {
                    retries = 0
                }
                run()
            }
        }
    }
}
