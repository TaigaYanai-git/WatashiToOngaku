import Foundation
import UserNotifications

/// 毎日決まった時刻に「今日の一曲を選ぼう」と知らせる
final class ReminderStore {
    static let shared = ReminderStore()
    private init() {}
    private let defaults = UserDefaults.standard
    private let identifier = "daily_song_reminder"

    private static let messagesJA = [
        "今日の一曲を選びましょう",
        "今日はどんな曲が聴きたい気分でしたか？",
        "今日を一曲で残しておきませんか？",
        "今日いちばん心に残った曲は？",
        "今日の気分に合う曲を記録しましょう",
    ]
    private static let messagesEN = [
        "Pick your song of the day",
        "What song matched your mood today?",
        "Save today as a single song",
        "Which song stayed with you today?",
        "Record a song for today's mood",
    ]

    static var messages: [String] { ThemeStore.shared.language == "en" ? messagesEN : messagesJA }

    var isEnabled: Bool {
        get { defaults.bool(forKey: "reminder_enabled") }
        set { defaults.set(newValue, forKey: "reminder_enabled") }
    }

    /// 既定は 21:00
    var hour: Int {
        get { defaults.object(forKey: "reminder_hour") == nil ? 21 : defaults.integer(forKey: "reminder_hour") }
        set { defaults.set(newValue, forKey: "reminder_hour") }
    }

    var minute: Int {
        get { defaults.integer(forKey: "reminder_minute") }
        set { defaults.set(newValue, forKey: "reminder_minute") }
    }

    func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = S("私と音楽", "Me & Music")
        content.body = Self.messages.randomElement() ?? Self.messages[0]
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func checkPermission(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }
}
