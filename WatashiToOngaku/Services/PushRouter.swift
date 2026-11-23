import CloudKit
import Combine
import UIKit
import UserNotifications

/// フレンドの投稿・コメントの通知（CloudKit の購読から届く）を受ける。
/// アプリを開いているときもバナーで出し、通知を押したらタイムラインを開く
@MainActor
final class PushRouter: ObservableObject {
    static let shared = PushRouter()
    /// 通知を押してタイムラインを開くよう頼まれた回数（増えたらタブを切り替える）
    @Published var openTimelineRequests = 0
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    private static func isFriendNotification(_ notification: UNNotification) -> Bool {
        CKNotification(fromRemoteNotificationDictionary: notification.request.content.userInfo) != nil
    }

    /// 開いているあいだに届いたフレンドの通知はバナーで出して、タイムラインを読み直す（毎日のリマインドはこれまでどおり出さない）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard Self.isFriendNotification(notification) else { return [] }
        await SocialStore.shared.refresh()
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard Self.isFriendNotification(response.notification) else { return }
        await MainActor.run { PushRouter.shared.openTimelineRequests += 1 }
    }
}
