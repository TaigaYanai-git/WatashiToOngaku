import Foundation
import SwiftData
import UIKit
import UserNotifications

/// 毎日決まった時刻に「今日の一曲を選ぼう」と知らせる。
/// その日の曲を記録済みなら鳴らさない。ローカル通知は届く時点で条件を見られないので、
/// 毎日くり返す通知1件ではなく、この先 `daysAhead` 日ぶんを日付ごとに予約し、記録済みの日は外す。
/// 記録の保存・削除、iCloud から記録が届いたとき、アプリが前面に来たとき、設定を変えたときに `refresh()` で予約し直す
final class ReminderStore {
    static let shared = ReminderStore()
    private init() {}
    private let defaults = UserDefaults.standard
    /// 1.0.3 までの毎日くり返す通知（残っていたら消す）
    private let legacyIdentifier = "daily_song_reminder"
    /// 日付ごとの通知は "daily_song_reminder_yyyy-MM-dd"
    private static let identifierPrefix = "daily_song_reminder_"
    /// iOS が予約しておける通知は 64 件まで。このアプリはほかにローカル通知を使わない
    static let daysAhead = 60
    @MainActor private var refreshTask: Task<Void, Never>?

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
    private static let messagesKO = [
        "오늘의 한 곡을 골라 보세요",
        "오늘은 어떤 곡이 듣고 싶은 기분이었나요?",
        "오늘을 한 곡으로 남겨 보지 않을래요?",
        "오늘 가장 마음에 남은 곡은?",
        "오늘 기분에 맞는 곡을 기록해 보세요",
    ]

    static var messages: [String] {
        switch ThemeStore.shared.language {
        case "en": return messagesEN
        case "ko": return messagesKO
        default: return messagesJA
        }
    }

    /// 既定はオン（通知を許可すれば、設定しなくても届く）。
    /// 一度でもリマインドの画面で保存した人は、その値（オフにした人はオフのまま）
    var isEnabled: Bool {
        get { defaults.object(forKey: "reminder_enabled") == nil ? true : defaults.bool(forKey: "reminder_enabled") }
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

    /// 予約する日。今日から `days` 日ぶんのうち、通知時刻がまだ来ていなくて、曲を記録していない日
    static func reminderDays(now: Date, hour: Int, minute: Int, recordedDayKeys: Set<String>,
                             days: Int = daysAhead, calendar: Calendar) -> [(dayKey: String, date: Date)] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > now else { return nil }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            return recordedDayKeys.contains(key) ? nil : (key, fire)
        }
    }

    /// 予約し直す。オフ・通知が許可されていないときは、予約をすべて消す
    @MainActor
    func refresh() {
        guard !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let todayKey = DayKey.string(from: now)
        // 今日以降に記録した日（先の日付は選べないので、実際には今日だけ）
        let descriptor = FetchDescriptor<SongEntry>(predicate: #Predicate { $0.dayKey >= todayKey })
        let recorded = Set(((try? AppContainer.shared.mainContext.fetch(descriptor)) ?? []).map(\.dayKey))
        let days = isEnabled
            ? Self.reminderDays(now: now, hour: hour, minute: minute, recordedDayKeys: recorded, calendar: calendar)
            : []
        let messages = Self.messages
        let title = S("Our Music", "Our Music")

        // 続けて呼ばれても、前の予約し直しが終わってから行う（古い予約が後から足されないように）
        let previous = refreshTask
        refreshTask = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            let allowed = status == .authorized || status == .provisional || status == .ephemeral
            let wanted = allowed ? days : []
            let wantedIDs = Set(wanted.map { Self.identifierPrefix + $0.dayKey })
            let pending = await center.pendingNotificationRequests().map(\.identifier)
            let stale = pending.filter { ($0.hasPrefix(Self.identifierPrefix) && !wantedIDs.contains($0)) || $0 == legacyIdentifier }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            // 今日の曲を選んだら、通知センターに残っている今日の通知も消す
            if recorded.contains(todayKey) {
                center.removeDeliveredNotifications(withIdentifiers: [Self.identifierPrefix + todayKey, legacyIdentifier])
            }
            for day in wanted {
                let content = UNMutableNotificationContent()
                content.title = title
                // 予約し直しても文言が変わらないよう、日付で選ぶ
                let seed = day.dayKey.unicodeScalars.reduce(0) { $0 + Int($1.value) }
                content.body = messages[seed % messages.count]
                content.sound = .default
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: day.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                // 同じ ID で足すと置き換わる
                try? await center.add(UNNotificationRequest(identifier: Self.identifierPrefix + day.dayKey,
                                                            content: content, trigger: trigger))
            }
        }
    }

    /// はじめての人に通知の許可を1回だけ求める（使い方ツアーのあと、ツアーを出さない人は起動時の広告の許可のあと）。
    /// まだ答えていない（.notDetermined）ときだけ出す。リマインドを自分でオフにした人と、
    /// -uiPreview・-tour（スクリーンショット用）の起動では出さない。許可されたらそのまま予約する
    @MainActor
    func requestPermissionIfNeeded() async {
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("-uiPreview"), !args.contains("-tour"), isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        // ダイアログは前面でないと出ないので、前面になってから画面が落ち着くまで少し置く（広告の許可と同じ）
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(300))
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { refresh() }
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
