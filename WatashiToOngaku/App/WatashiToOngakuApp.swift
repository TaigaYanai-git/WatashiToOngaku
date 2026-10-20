import CloudKit
import SwiftData
import SwiftUI

@MainActor
enum AppContainer {
    static let shared: ModelContainer = {
        let preview = ProcessInfo.processInfo.arguments.contains("-uiPreview")
        // フレンド機能のために iCloud（CloudKit）の権限を持っているが、記録の保存は端末内だけにする。
        // （SwiftData の自動同期は使わず、共有する投稿は SocialStore が自分で CloudKit に置く）
        let config = ModelConfiguration(isStoredInMemoryOnly: preview, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: SongEntry.self, configurations: config)
        } catch {
            fatalError("データベースを開けませんでした: \(error)")
        }
    }()
}

/// 招待リンク（CloudKit の共有リンク）をタップしてアプリが開いたときに受け取る
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            let social = SocialStore.shared
            if social.state != .ready { await social.start() }
            _ = await social.accept(metadata)
            PendingInvite.shared.result = social.lastError == nil
                ? S("フレンドになりました！", "You're now friends!")
                : (social.lastError ?? "")
        }
    }
}

/// 招待リンクを受け入れた結果をアラートで出すため
@MainActor
final class PendingInvite: ObservableObject {
    static let shared = PendingInvite()
    @Published var result: String?
}

@main
struct WatashiToOngakuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uiPreview") {
            SampleData.insert(into: AppContainer.shared.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(AppContainer.shared)
    }
}

/// テーマ（色・ダークモード・言語）をアプリ全体に反映する
private struct AppRootView: View {
    @StateObject private var theme = ThemeStore.shared
    @StateObject private var router = NavigationRouter()
    @ObservedObject private var invite = PendingInvite.shared

    var body: some View {
        TabView(selection: Binding(
            get: { router.selectedTab },
            set: { tab in
                // 「今日」タブをもう一度押したら今日に戻る
                if tab == .today && router.selectedTab == .today { router.targetDate = Date() }
                router.selectedTab = tab
            }
        )) {
            TodayView()
                .tabItem { Label { Text(S("今日", "Today")) } icon: { Image("TodayTabIcon") } }
                .tag(AppTab.today)
            TimelineView()
                .tabItem { Label(S("タイムライン", "Timeline"), systemImage: "person.2") }
                .tag(AppTab.timeline)
            SongCalendarView()
                .tabItem { Label(S("カレンダー", "Calendar"), systemImage: "calendar") }
                .tag(AppTab.calendar)
            ReviewView()
                .tabItem { Label(S("ふりかえり", "Look Back"), systemImage: "chart.bar.doc.horizontal") }
                .tag(AppTab.review)
            SettingsView()
                .tabItem { Label(S("設定", "Settings"), systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(.dlPrimary)
        .id(theme.language)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .environmentObject(theme)
        .environmentObject(router)
        .task {
            if !ProcessInfo.processInfo.arguments.contains("-uiPreview") { await SocialStore.shared.start() }
        }
        .alert(Text(verbatim: invite.result ?? ""),
               isPresented: Binding(get: { invite.result != nil }, set: { if !$0 { invite.result = nil } })) {
            Button("OK") { router.selectedTab = .timeline }
        }
        .onAppear {
            if let tab = UserDefaults.standard.string(forKey: "initialTab") {
                router.selectedTab = ["timeline": .timeline, "calendar": .calendar, "review": .review, "settings": .settings][tab] ?? .today
            }
        }
    }
}
