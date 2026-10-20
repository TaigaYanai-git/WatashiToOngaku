import SwiftData
import SwiftUI

@MainActor
enum AppContainer {
    static let shared: ModelContainer = {
        let preview = ProcessInfo.processInfo.arguments.contains("-uiPreview")
        let config = ModelConfiguration(isStoredInMemoryOnly: preview)
        do {
            return try ModelContainer(for: SongEntry.self, configurations: config)
        } catch {
            fatalError("データベースを開けませんでした: \(error)")
        }
    }()
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
        .onAppear {
            if let tab = UserDefaults.standard.string(forKey: "initialTab") {
                router.selectedTab = ["calendar": .calendar, "review": .review, "settings": .settings][tab] ?? .today
            }
        }
    }
}
