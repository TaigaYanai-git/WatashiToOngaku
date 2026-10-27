import Combine
import StoreKit

/// 「Our Music Plus」（自動更新サブスクリプション）の購入状態。
/// 記録・フレンド・9色のテーマカラーと背景・アイコン・自分のふりかえりのプレイリストは無料。
/// Plus では、タイムラインの追加と1年前までの表示、フレンドの月・年のプレイリスト、カスタムカラー、アイコンの固定が使え、広告が出ない。
@MainActor
final class PlusStore: ObservableObject {
    static let shared = PlusStore()

    static let productIDs = ["com.taigayanai.watashitoongaku.plus.monthly",
                             "com.taigayanai.watashitoongaku.plus.yearly"]

    @Published private(set) var isPlus: Bool

    #if DEBUG
    /// 開発中に Plus の画面を確かめるためのスイッチ（App Store に出すビルドには入らない）
    @Published var debugOverride: Bool {
        didSet { UserDefaults.standard.set(debugOverride, forKey: "plus_debugOverride"); Task { await refresh() } }
    }
    #endif

    private var updates: Task<Void, Never>?

    private init() {
        // 起動直後に色やアイコンが一瞬戻らないよう、前回の状態から始める
        isPlus = UserDefaults.standard.bool(forKey: "plus_active")
        #if DEBUG
        debugOverride = UserDefaults.standard.bool(forKey: "plus_debugOverride")
            || ProcessInfo.processInfo.arguments.contains("-plus")
        #endif
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        #if DEBUG
        active = active || debugOverride
        #endif
        let changed = isPlus != active
        isPlus = active
        UserDefaults.standard.set(active, forKey: "plus_active")
        if !active, ThemeStore.shared.isCustom {
            // Plus が終わったら、カスタムカラーからブラックに戻す
            ThemeStore.shared.accentIndex = 0
        }
        // 固定していたアイコンは Plus のときだけ効くので、Plus が始まった・終わったら付け直す
        if changed { AppIconManager.apply() }
    }
}
