import CoreData
import SwiftData
import SwiftUI

@MainActor
enum AppContainer {
    /// 記録を自分の iCloud（非公開データベース）にも保存して、アプリを入れ直しても戻せるようにする。
    /// 開発用：シミュレータは実機と同じ Apple アカウントなので、試しの記録が実機の日記に混ざらないよう、
    /// -cloudSync YES を付けたときだけ同期する
    static var syncsToICloud: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiPreview") { return false }
        #if DEBUG && targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "cloudSync")
        #else
        return true
        #endif
    }

    static let shared: ModelContainer = {
        let preview = ProcessInfo.processInfo.arguments.contains("-uiPreview")
        if !preview { EntrySync.dropOldUniqueIndex(at: URL.applicationSupportDirectory.appending(path: "default.store")) }
        // 共有する投稿は SocialStore が公開データベースに置く。こちらは本人だけが見る控え
        let config = ModelConfiguration(isStoredInMemoryOnly: preview,
                                        cloudKitDatabase: syncsToICloud ? .private(SocialStore.containerID) : .none)
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
    /// フレンドの通知を受けるため
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
    @ObservedObject private var push = PushRouter.shared
    @Environment(\.scenePhase) private var scenePhase

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
        // はじめて開いた人への使い方ツアー（画面のボタンを照らして説明する）
        .overlay { AppTourOverlay() }
        .id(theme.language)
        // 日付や時刻の選択などのシステムの表示も、アプリで選んだ言語にする
        .environment(\.locale, .app)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .environmentObject(theme)
        .environmentObject(router)
        // 起動したら最初に、広告の識別子を使ってよいかを聞く（答えが出るまで広告 SDK は動かない）
        .task {
            let args = ProcessInfo.processInfo.arguments
            // スクリーンショット用：-tour で必ずツアーを出す（-tourStep N でその手順から）
            if args.contains("-tour") {
                if let i = args.firstIndex(of: "-tourStep"), args.indices.contains(i + 1), let n = Int(args[i + 1]) {
                    AppTour.shared.start(); AppTour.shared.stepIndex = n
                } else {
                    AppTour.shared.start()
                }
                return
            }
            guard !args.contains("-uiPreview") else { return }
            await TrackingConsent.requestIfNeeded()
            // 広告の許可に答えたあとで、はじめての人に使い方を見せる
            // ツアーを出す人は、ツアーを閉じたあとに通知の許可を求める（AppTour.finish）。
            // 出さない人（前から使っている人など）には、広告の許可のあとで求める（まだ答えていなければ）
            if !AppTour.shared.startIfNeeded() {
                await ReminderStore.shared.requestPermissionIfNeeded()
            }
        }
        // iCloud から記録が届いたら、同じ日が2件になっていないか確かめる
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
            EntrySync.mergeDuplicates(in: AppContainer.shared.mainContext)
            // ほかの端末で今日の曲を選んでいたら、今日のリマインドを取り消す
            ReminderStore.shared.refresh()
        }
        // 前面に来るたびにリマインドを予約し直す（日付が進んだ・iCloud から記録が届いた・通知の許可を変えたなど）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ReminderStore.shared.refresh() }
        }
        // フレンドの投稿・コメントの通知を押したら、タイムラインを開いて読み直す
        .onChange(of: push.openTimelineRequests) { _, _ in
            router.selectedTab = .timeline
            Task { await SocialStore.shared.refresh() }
        }
        .task {
            EntrySync.mergeDuplicates(in: AppContainer.shared.mainContext)
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
        // 招待リンク（https://tora-apple.github.io/ourmusic/add?c=コード のユニバーサルリンク、または watashitoongaku://add?c=コード）で開いたらフレンド申請を送る
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
                let result = await social.addFriend(url: url)
                invite.result = result.map(SocialStore.message(for:))
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
