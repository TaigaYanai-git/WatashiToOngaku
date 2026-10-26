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
    @ObservedObject private var plus = PlusStore.shared
    @State private var showPlus = false
    @State private var showManageSubscription = false
    @State private var showBlocked = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileSection
                    if social.state == .ready { friendsSection }
                    plusSection
                    themeSection
                    languageSection
                    settingsSection
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

                                Text(accent.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(theme.accentIndex == accent.id ? .dlPrimary : .dlTextSub)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

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
            .onChange(of: theme.accentIndex) { _, index in AppIconManager.apply(accentIndex: index) }
            .onChange(of: theme.isDark) { _, isDark in AppIconManager.apply(isDark: isDark) }
        }
    }

    private func bgPatternButton(pattern: BgPattern) -> some View {
        let selected = theme.bgPatternIndex == pattern.rawValue
        let label = theme.language == "en" ? pattern.labelEn : pattern.label
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
                         : S("1年のプレイリスト、長い期間のカスタムプレイリストなど", "Yearly playlists, longer custom playlists and more"))
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
            Text("言語 / Language")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
                .padding(.horizontal, 20)

            Picker("", selection: $theme.language) {
                Text("日本語").tag("ja")
                Text("English").tag("en")
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
        }
    }

    // MARK: - フレンド

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(S("フレンド", "Friends"))
            row(icon: "hand.raised.slash", title: S("ブロックしたユーザー", "Blocked Users"),
                detail: social.blockedUsers.isEmpty ? S("なし", "None") : S("\(social.blockedUsers.count)人", "\(social.blockedUsers.count)")) {
                showBlocked = true
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
                if let url = Bundle.main.urlSetting("REPO_URL") {
                    row(icon: "chevron.left.forwardslash.chevron.right", title: S("ソースコード", "Source Code"), detail: "") { openURL(url) }
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
