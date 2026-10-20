import Combine
import Foundation

enum AppTab: Hashable { case today, calendar, review, settings }

/// タブの切り替えと、今日の画面で表示する日付
final class NavigationRouter: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var targetDate = Date()
}
