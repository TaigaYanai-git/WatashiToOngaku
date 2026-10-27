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

/// 招待リンクを受け入れた結果をアラートで出すため
@MainActor
final class PendingInvite: ObservableObject {
    static let shared = PendingInvite()
    @Published var result: String?
}

@main
struct WatashiToOngakuApp: App {
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
        // 日付や時刻の選択などのシステムの表示も、アプリで選んだ言語にする
        .environment(\.locale, .app)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .environmentObject(theme)
        .environmentObject(router)
        .task {
            await PlusStore.shared.refresh()
            guard !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
            // アプリ内のダークモード・テーマカラーとホーム画面のアイコンがずれていたら合わせる
            AppIconManager.syncOnLaunch()
            // 前に選んだ曲にもアーティスト ID を入れて、表記の違う同じアーティストをまとめる
            Task {
                await AppleMusicService.fillArtistIDs(in: AppContainer.shared.mainContext)
                await SocialStore.shared.uploadChanges()
            }
            await SocialStore.shared.start()
        }
        // 招待リンク（watashitoongaku://add?c=コード）で開いたらフレンド申請を送る
        .onOpenURL { url in
            guard SocialStore.code(in: url) != nil else { return }
            Task {
                let social = SocialStore.shared
                if social.state != .ready { await social.start() }
                if social.state != .ready {
                    router.selectedTab = .timeline
                    invite.result = S("フレンドを追加するには、先にタイムラインでニックネームを決めてください", "Set your nickname in Timeline first, then open the invite again")
                    return
                }
                invite.result = await social.addFriend(url: url).map(SocialStore.message(for:))
                    ?? (social.lastError ?? S("申請できませんでした", "Couldn't send the request"))
            }
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
