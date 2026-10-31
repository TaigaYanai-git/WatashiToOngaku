import SwiftUI
import UserNotifications

/// 設定（テーマ・言語・リマインダー）。V-Diary のプロフィール画面の設定部分を元にしたもの。
struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var router: NavigationRouter
    @ObservedObject private var social = SocialStore.shared
    @Environment(\.openURL) private var openURL
    @State private var showReminderSheet = false
    @State private var reminderSummary = ""
    @AppStorage(AppIconManager.followsThemeKey) private var iconFollowsTheme = false
    @State private var showIconPicker = false
    @ObservedObject private var plus = PlusStore.shared
    @State private var showPlus = false
    @State private var showManageSubscription = false
    @State private var showBlocked = false
    @State private var showBirthday = false
    @AppStorage(Birthday.key) private var birthdayStored: Double = 0
    @State private var restoring = false
    @State private var restoreMessage: String?
    @State private var confirmLeave = false
    @State private var leaving = false
    @State private var leaveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileSection
                    plusSection
                    themeSection
                    languageSection
                    settingsSection
                    if social.state == .ready { friendsSection }
                    aboutSection
                }
                .padding(.vertical, 16)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("設定", "Settings")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .sheet(isPresented: $showReminderSheet, onDismiss: updateReminderSummary) { ReminderSheet() }
            .sheet(isPresented: $showPlus) { PlusView() }
            .sheet(isPresented: $showBlocked) { BlockedUsersView() }
            .sheet(isPresented: $showBirthday) { BirthdaySheet() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .onAppear(perform: updateReminderSummary)
        }
    }

    // MARK: - Theme section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: S("テーマカラー", "Theme Color"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
                .padding(.horizontal, 20)

            // Accent colour picker (scrollable for 8 options)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ThemeStore.accents) { accent in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                theme.accentIndex = accent.id
                            }
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(accent.primary)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle().strokeBorder(
                                                Color.dlDivider,
                                                lineWidth: accent.needsBorder ? 1.5 : 0
                                            )
                                        )
                                        .shadow(
                                            color: accent.primary.opacity(theme.accentIndex == accent.id ? 0.5 : 0.18),
                                            radius: theme.accentIndex == accent.id ? 8 : 3, y: 2
                                        )
                                    if theme.accentIndex == accent.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundColor(accent.needsBorder ? Color.dlText : .white)
                                    }
                                }
                                .scaleEffect(theme.accentIndex == accent.id ? 1.12 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: theme.accentIndex)

                                Text(verbatim: S(accent.name, accent.name))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(theme.accentIndex == accent.id ? .dlPrimary : .dlTextSub)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    customColorSwatch
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            Text(verbatim: S("カスタム（Plus）の色は、アプリのアイコンには反映されません",
                             "Custom colors (Plus) aren't applied to the app icon",
                             "사용자 지정 색상（Plus）은 앱 아이콘에는 반영되지 않습니다"))
                .font(.caption2)
                .foregroundColor(.dlTextSub)
                .padding(.horizontal, 20)

            // Background pattern picker
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: S("背景テーマ", "Background Pattern"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.dlTextSub)
                    .padding(.horizontal, 20)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(BgPattern.allCases, id: \.rawValue) { pattern in
                        bgPatternButton(pattern: pattern)
                    }
                }
                .padding(.horizontal, 20)
            }

            // Dark mode toggle
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.dlPrimaryBg)
                        .frame(width: 36, height: 36)
                    Image(systemName: theme.isDark ? "moon.fill" : "moon")
                        .font(.body)
                        .foregroundColor(.dlPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: S("ダークモード", "Dark Mode"))
                        .font(.subheadline)
                        .foregroundColor(.dlText)
                    Text(verbatim: S("アプリのアイコンも黒になります（iOS のお知らせが出ます）", "The app icon turns dark too (iOS shows a notice)"))
                        .font(.caption2)
                        .foregroundColor(.dlTextSub)
                }
                Spacer()
                Toggle("", isOn: $theme.isDark)
                    .tint(.dlPrimary)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.dlCard)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)

            // アプリアイコンもテーマカラーに合わせる
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.dlPrimaryBg).frame(width: 36, height: 36)
                    Image(systemName: "app.badge").font(.body).foregroundColor(.dlPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: S("アイコンもテーマカラーにする", "Match App Icon to Theme"))
                        .font(.subheadline)
                        .foregroundColor(.dlText)
                    Text(verbatim: S("切り替えるたびに iOS のお知らせが出ます", "iOS shows a notice each time it changes"))
                        .font(.caption2)
                        .foregroundColor(.dlTextSub)
                }
                Spacer()
                Toggle("", isOn: $iconFollowsTheme)
                    .tint(.dlPrimary)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.dlCard)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            .onChange(of: iconFollowsTheme) { _, _ in AppIconManager.apply() }

            // Plus：ダークモードやテーマカラーに左右されないアイコンに固定する
            Button {
                if plus.isPlus { showIconPicker = true } else { showPlus = true }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.dlPrimaryBg).frame(width: 36, height: 36)
                        Image(systemName: "pin").font(.body).foregroundColor(.dlPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: S("アイコンを固定（Plus）", "Fix App Icon (Plus)", "아이콘 고정（Plus）"))
                            .font(.subheadline)
                            .foregroundColor(.dlText)
                        Text(verbatim: S("ダークモードやテーマカラーを変えても、選んだアイコンのままにします",
                                         "Keep the icon you choose, whatever the theme or dark mode",
                                         "다크 모드나 테마 색상을 바꿔도 고른 아이콘을 유지합니다"))
                            .font(.caption2)
                            .foregroundColor(.dlTextSub)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Text(verbatim: AppIconManager.fixed == nil ? S("オフ", "Off", "끔") : S("オン", "On", "켬"))
                        .font(.subheadline)
                        .foregroundColor(.dlTextSub)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.dlTextLight)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.dlCard)
                .cornerRadius(16)
                .padding(.horizontal, 20)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showIconPicker) { AppIconPickerSheet() }
            .onChange(of: theme.accentIndex) { _, index in AppIconManager.apply(accentIndex: index) }
            .onChange(of: theme.isDark) { _, isDark in AppIconManager.apply(isDark: isDark) }
        }
    }

    /// Plus：好きな色を選べるテーマカラー
    private var customColorSwatch: some View {
        VStack(spacing: 5) {
            ZStack {
                if plus.isPlus {
                    ColorPicker("", selection: Binding(
                        get: { theme.customColor },
                        set: { theme.customColor = $0; theme.accentIndex = ThemeStore.customIndex }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36, height: 36)
                    .scaleEffect(theme.isCustom ? 1.12 : 1.0)
                } else {
                    Button { showPlus = true } label: {
                        Circle()
                            .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            .frame(width: 36, height: 36)
                            .overlay(Image(systemName: "lock.fill").font(.caption2.weight(.bold)).foregroundColor(.white))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(verbatim: S("カスタム", "Custom", "사용자 지정"))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(theme.isCustom ? .dlPrimary : .dlTextSub)
        }
        .accessibilityLabel(S("カスタムカラー（Plus）", "Custom Color (Plus)", "사용자 지정 색상（Plus）"))
    }

    private func bgPatternButton(pattern: BgPattern) -> some View {
        let selected = theme.bgPatternIndex == pattern.rawValue
        let label = S(pattern.label, pattern.labelEn, pattern.labelKo)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                theme.bgPatternIndex = pattern.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.dlCard)
                        .frame(width: 72, height: 48)
                    // Live mini-preview
                    if pattern != .none {
                        AppBackgroundPattern(patternIndex: pattern.rawValue, primary: theme.primary)
                            .frame(width: 72, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            selected ? Color.dlPrimary : Color.dlDivider,
                            lineWidth: selected ? 2 : 1
                        )
                        .frame(width: 72, height: 48)
                }
                Text(label)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundColor(selected ? .dlPrimary : .dlTextSub)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plus

    private var plusSection: some View {
        Button {
            if plus.isPlus { showManageSubscription = true } else { showPlus = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(LinearGradient.dlPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: S("Our Music Plus", "Our Music Plus")).font(.subheadline.weight(.semibold)).foregroundColor(.dlText)
                    Text(verbatim: plus.isPlus
                         ? S("ご利用ありがとうございます。タップで登録を管理", "Thanks for your support. Tap to manage")
                         : S("タイムラインを5つ追加・1年前まで遡れる・広告なし", "5 more timelines, a year of history, no ads", "타임라인 5개 추가 · 1년 기록 · 광고 없음"))
                        .font(.caption)
                        .foregroundColor(.dlTextSub)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.dlTextLight)
            }
            .padding(16)
            .background(Color.dlCard)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "言語 / Language / 언어")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
                .padding(.horizontal, 20)

            Picker("", selection: $theme.language) {
                Text("日本語").tag("ja")
                Text("English").tag("en")
                Text("한국어").tag("ko")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - プロフィール

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(S("プロフィール", "Profile"))
            Group {
                if social.state == .ready {
                    ProfileHeader()
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 10) {
                        Text(verbatim: S("フレンド機能をはじめると、アイコンとニックネームを設定できます",
                                         "Start Friends to set your icon and nickname"))
                            .font(.subheadline)
                            .foregroundColor(.dlTextSub)
                            .multilineTextAlignment(.center)
                        Button(S("タイムラインではじめる", "Start in Timeline")) { router.selectedTab = .timeline }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(16)
            .background(Color.dlCard)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            .padding(.horizontal, 20)
            // 年齢ごとのプレイリスト（ふりかえり）に使う
            row(icon: "gift", title: S("誕生日", "Birthday"),
                detail: Birthday.date(from: birthdayStored)?.formatted(.dateTime.locale(.app).year().month(.defaultDigits).day()) ?? S("未登録", "Not set")) {
                showBirthday = true
            }
        }
    }

    // MARK: - フレンド

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(S("フレンド", "Friends"))
            VStack(spacing: 10) {
                row(icon: "hand.raised.slash", title: S("ブロックしたユーザー", "Blocked Users"),
                    detail: social.blockedUsers.isEmpty ? S("なし", "None") : S("\(social.blockedUsers.count)人", "\(social.blockedUsers.count)", "\(social.blockedUsers.count)명")) {
                    showBlocked = true
                }
                // アプリを入れ直したときなどに、フレンドに共有した曲から記録を戻す
                row(icon: "icloud.and.arrow.down", title: S("iCloud から曲を戻す", "Restore Songs from iCloud"),
                    detail: restoring ? S("戻しています…", "Restoring…") : "") {
                    guard !restoring else { return }
                    restoring = true
                    Task {
                        let count = await social.restoreFromCloud()
                        restoring = false
                        restoreMessage = count > 0
                            ? S("\(count)日分の曲を戻しました", "Restored songs for \(count) days", "\(count)일분의 곡을 복원했습니다")
                            : S("戻せる曲はありませんでした。フレンドに共有した日の曲だけ戻せます", "Nothing to restore. Only songs shared with friends can be restored")
                    }
                }
                // iCloud に置いたプロフィールと投稿をすべて消す（アカウントの削除にあたる）
                row(icon: "person.crop.circle.badge.xmark", title: S("フレンド機能をやめる", "Stop Using Friends", "친구 기능 그만두기"),
                    detail: leaving ? S("削除しています…", "Deleting…", "삭제하는 중…") : "") {
                    guard !leaving else { return }
                    confirmLeave = true
                }
                Text(verbatim: S("iCloud に置いたニックネーム・アイコン・フレンドに共有した曲とメモを削除し、すべてのフレンドとのつながりがなくなります。元には戻せません。\nこの iPhone の今日・カレンダー・ふりかえりの記録は残ります。ただし、アプリを入れ直したときに iCloud から記録を戻すことはできなくなります。",
                                 "Deletes your nickname, icon, and the songs and notes you shared with friends from iCloud, and disconnects you from all friends. This can't be undone.\nYour songs in Today, Calendar, and Look Back stay on this iPhone, but you won't be able to restore them from iCloud if you reinstall the app.",
                                 "iCloud에 저장된 닉네임·아이콘·친구에게 공유한 곡과 메모가 삭제되고, 모든 친구와의 연결이 없어집니다. 되돌릴 수 없습니다.\n이 iPhone의 오늘·캘린더·돌아보기 기록은 남습니다. 단, 앱을 다시 설치했을 때 iCloud에서 기록을 복원할 수 없게 됩니다."))
                    .font(.caption)
                    .foregroundColor(.dlTextSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }
            .alert(Text(verbatim: restoreMessage ?? ""), isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog(Text(verbatim: S("フレンド機能をやめて、データを削除しますか？", "Stop using Friends and delete your data?", "친구 기능을 그만두고 데이터를 삭제할까요?")),
                                isPresented: $confirmLeave, titleVisibility: .visible) {
                Button(S("削除する", "Delete", "삭제"), role: .destructive) {
                    leaving = true
                    Task {
                        leaveFailed = !(await social.leave())
                        leaving = false
                    }
                }
            } message: {
                Text(verbatim: S("iCloud に置いたニックネーム・アイコン・共有した曲を削除し、フレンドとのつながりもなくなります。この端末の記録は残ります。元には戻せません。",
                                 "Your nickname, icon, and shared songs will be deleted from iCloud, and you'll be disconnected from all friends. Songs on this device are kept. This can't be undone.",
                                 "iCloud에 저장된 닉네임·아이콘·공유한 곡이 삭제되고 친구와의 연결도 없어집니다. 이 기기의 기록은 남습니다. 되돌릴 수 없습니다."))
            }
            .alert(Text(verbatim: S("削除できませんでした。通信できる場所でもう一度お試しください", "Couldn't delete your data. Check your connection and try again.", "삭제하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.")),
                   isPresented: $leaveFailed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(S("通知", "Notifications"))
            row(icon: "bell", title: S("毎日のリマインダー", "Daily Reminder"), detail: reminderSummary) {
                showReminderSheet = true
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(S("このアプリについて", "About"))
            VStack(spacing: 10) {
                if let url = Bundle.main.urlSetting("PRIVACY_POLICY_URL") {
                    row(icon: "hand.raised", title: S("プライバシーポリシー", "Privacy Policy"), detail: "") { openURL(url) }
                }
            }
            Link(destination: URL(string: "https://www.flaticon.com/free-icon/vinyl_812680")!) {
                Text(verbatim: "Vinyl icon by Those Icons – Flaticon")
                    .font(.caption)
                    .foregroundColor(.dlTextSub)
                    .underline()
            }
            .padding(.horizontal, 20)
            Text(verbatim: S("曲の検索と試聴には Apple Music を使います。選んだ曲・メモはこの iPhone の中だけに保存されます。",
                             "Songs are searched and previewed with Apple Music. Your songs and notes stay on this iPhone."))
                .font(.caption)
                .foregroundColor(.dlTextSub)
                .padding(.horizontal, 20)
            #if DEBUG
            Toggle(S("開発用：Plus を有効にする", "Debug: Enable Plus"), isOn: $plus.debugOverride)
                .font(.caption)
                .tint(.dlPrimary)
                .padding(.horizontal, 20)
            #endif
            Text(verbatim: "\(S("バージョン", "Version")) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")")
                .font(.caption)
                .foregroundColor(.dlTextLight)
                .frame(maxWidth: .infinity)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.dlTextSub)
            .padding(.horizontal, 20)
    }

    private func row(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.dlPrimaryBg).frame(width: 36, height: 36)
                    Image(systemName: icon).font(.body).foregroundColor(.dlPrimary)
                }
                Text(verbatim: title).font(.subheadline).foregroundColor(.dlText)
                Spacer()
                if !detail.isEmpty {
                    Text(verbatim: detail).font(.subheadline).foregroundColor(.dlTextSub)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.dlTextLight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.dlCard)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private func updateReminderSummary() {
        let s = ReminderStore.shared
        reminderSummary = s.isEnabled ? String(format: "%d:%02d", s.hour, s.minute) : S("オフ", "Off")
    }
}

extension Bundle {
    func urlSetting(_ key: String) -> URL? {
        (object(forInfoDictionaryKey: key) as? String).flatMap(URL.init(string:))
    }
}

// MARK: - Reminder sheet

private struct ReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isEnabled: Bool
    @State private var reminderTime: Date
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined

    init() {
        let s   = ReminderStore.shared
        let cal = Calendar.current
        var c   = DateComponents()
        c.hour   = s.hour
        c.minute = s.minute
        _isEnabled    = State(initialValue: s.isEnabled)
        _reminderTime = State(initialValue: cal.date(from: c) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DlBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Enable toggle
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: S("毎日リマインド", "Daily Reminder"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.dlText)
                                Text(verbatim: S("設定した時刻に「今日の一曲」を選ぶ通知を送ります", "Get a daily nudge to pick your song of the day"))
                                    .font(.caption)
                                    .foregroundColor(.dlTextSub)
                            }
                            Spacer()
                            Toggle("", isOn: $isEnabled)
                                .tint(.dlPrimary)
                                .labelsHidden()
                        }
                        .padding(16)
                        .background(Color.dlCard)
                        .cornerRadius(16)

                        // Time picker (visible when enabled)
                        if isEnabled {
                            HStack {
                                Label(S("通知時刻", "Notification Time"), systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.dlText)
                                Spacer()
                                DatePicker("", selection: $reminderTime,
                                           displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .tint(.dlPrimary)
                            }
                            .padding(16)
                            .background(Color.dlCard)
                            .cornerRadius(16)
                        }

                        // Permission denied warning
                        if permissionStatus == .denied {
                            Button {
                                openURL(URL(string: UIApplication.openSettingsURLString)!)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text(verbatim: S("通知が許可されていません。設定アプリで許可してください。", "Notifications not allowed. Enable them in Settings."))
                                        .font(.caption)
                                        .foregroundColor(.dlText)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.10))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }

                    }
                    .padding(20)
                }
            }
            .navigationTitle(Text(verbatim: S("リマインド", "Reminder")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(S("キャンセル", "Cancel")) { dismiss() }
                        .foregroundColor(.dlTextSub)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("保存", "Save")) { save() }
                        .font(.body.weight(.semibold))
                        .foregroundColor(.dlPrimary)
                }
            }
        }
        .onAppear {
            ReminderStore.shared.checkPermission { permissionStatus = $0 }
        }
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        ReminderStore.shared.hour    = comps.hour   ?? 21
        ReminderStore.shared.minute  = comps.minute ?? 0
        ReminderStore.shared.isEnabled = isEnabled

        if isEnabled {
            ReminderStore.shared.requestPermission { granted in
                if granted {
                    ReminderStore.shared.schedule()
                } else {
                    permissionStatus = .denied
                    return
                }
            }
        } else {
            ReminderStore.shared.cancelAll()
        }
        dismiss()
    }
}
