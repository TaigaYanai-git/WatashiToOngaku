import MusicKit
import SwiftUI

/// プレイリストの期間
enum PlaylistSpan: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return S("日", "Day")
        case .week: return S("週", "Week")
        case .month: return S("月", "Month")
        case .year: return S("年", "Year")
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    /// みんなのプレイリストで Plus が必要な期間
    var needsPlus: Bool { self == .month || self == .year }

    func interval(containing date: Date) -> DateInterval {
        Calendar.current.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    /// 2026年10月26日 / 10月20日〜26日 / 2026年10月 / 2026年
    func title(for date: Date) -> String {
        let locale = Locale(identifier: ThemeStore.shared.language == "en" ? "en_US" : "ja_JP")
        switch self {
        case .day:
            return date.formatted(.dateTime.locale(locale).year().month().day())
        case .week:
            let range = interval(containing: date)
            let last = range.end.addingTimeInterval(-1)
            return "\(range.start.formatted(.dateTime.locale(locale).month().day())) – \(last.formatted(.dateTime.locale(locale).month().day()))"
        case .month:
            return date.formatted(.dateTime.locale(locale).year().month())
        case .year:
            return date.formatted(.dateTime.locale(locale).year())
        }
    }
}

/// 「Apple Musicで再生」「ライブラリに保存」のボタン
struct PlaylistActions: View {
    /// 曲のカタログ ID（再生する順）
    let songIDs: [String]
    let name: String
    let description: String
    /// 同じ期間のプレイリストを作り直さず、入れ替えるための名前
    let key: String

    @State private var working: String?
    @State private var message: String?
    @State private var showOffer = false
    @State private var savedName: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                button("play.fill", S("Apple Musicで再生", "Play in Apple Music"), id: "play") {
                    try await AppleMusicService.play(songIDs)
                }
                button("plus.square.on.square", S("ライブラリに保存", "Save to Library"), id: "save") {
                    try await AppleMusicService.save(songIDs, name: name, description: description, key: key)
                    savedName = name
                }
            }
            if let savedName {
                Button {
                    AppleMusicService.openMusicApp()
                } label: {
                    Label(S("「\(savedName)」を保存しました。ミュージックで開く", "Saved \"\(savedName)\". Open Music"),
                          systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.dlPrimary)
                }
            }
        }
        .disabled(songIDs.isEmpty)
        .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .musicSubscriptionOffer(isPresented: $showOffer, options: MusicSubscriptionOffer.Options(messageIdentifier: .playMusic))
    }

    private func button(_ symbol: String, _ title: String, id: String, action: @escaping () async throws -> Void) -> some View {
        Button {
            working = id
            Task {
                defer { working = nil }
                do {
                    try await action()
                } catch AppleMusicService.Failure.noSubscription(let canSubscribe) where canSubscribe {
                    showOffer = true
                } catch {
                    message = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 6) {
                if working == id { ProgressView().tint(.white) } else { Image(systemName: symbol) }
                Text(verbatim: title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(id == "play" ? .white : .dlPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(id == "play" ? AnyShapeStyle(LinearGradient.dlPrimary) : AnyShapeStyle(Color.dlPrimaryBg))
            .cornerRadius(14)
        }
        .disabled(working != nil)
    }
}

/// プレイリストの1曲
struct PlaylistRow: View {
    let post: FriendPost
    var showsPerson = true

    var body: some View {
        HStack(spacing: 12) {
            PlayableArtwork(id: post.id, artworkURL: post.artworkURL, previewURL: post.previewURL, size: 52, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                Text(post.artist).font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                if showsPerson {
                    AvatarView(code: post.friend.code, version: post.friend.avatarVersion, nickname: post.friend.nickname, size: 22)
                }
                if let day = post.day {
                    Text(day, format: .dateTime.month(.defaultDigits).day())
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.dlTextSub)
                }
            }
        }
    }
}

/// 自分を含めたフレンドみんなが選んだ曲の、日・週・月・年のプレイリスト
struct GroupPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @State var span: PlaylistSpan
    @State private var anchor = Date()
    @State private var posts: [FriendPost] = []
    @State private var loading = false

    private var range: DateInterval { span.interval(containing: anchor) }
    private var canGoForward: Bool { range.end <= Date() }
    private var locked: Bool { span.needsPlus && !plus.isPlus }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $span) {
                        ForEach(PlaylistSpan.allCases) { span in
                            Text(span.needsPlus && !plus.isPlus ? "\(span.label) 🔒" : span.label).tag(span)
                        }
                    }
                    .pickerStyle(.segmented)

                    PeriodHeader(title: span.title(for: anchor), canGoForward: canGoForward) { shift($0) }

                    if locked {
                        PlusLockedCard(title: S("みんなの\(span == .month ? "1か月" : "1年")ぶんの曲を、Apple Music でまとめて聴けます",
                                                "Listen to everyone's songs from the whole \(span == .month ? "month" : "year")"))
                    } else if loading && posts.isEmpty {
                        ProgressView().tint(.dlPrimary).padding(40)
                    } else if posts.isEmpty {
                        emptyCard
                    } else {
                        summary
                        PlaylistActions(songIDs: posts.map(\.songID),
                                        name: S("私と音楽 みんなの\(span.title(for: anchor))", "Me & Music: Everyone, \(span.title(for: anchor))"),
                                        description: S("私と音楽で、自分とフレンドが選んだ曲", "Songs picked by me and my friends in Me & Music"),
                                        key: "group-\(span.rawValue)-\(DayKey.string(from: range.start))")
                        VStack(spacing: 12) {
                            ForEach(posts) { PlaylistRow(post: $0) }
                        }
                        .dlCard()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("みんなのプレイリスト", "Everyone's Playlist")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .task(id: "\(span.rawValue)-\(DayKey.string(from: range.start))-\(locked)") { await load() }
            .onDisappear { PreviewPlayer.shared.stop() }
        }
    }

    private var summary: some View {
        let people = Set(posts.map(\.friend.code)).count
        return Text(verbatim: S("\(people)人が選んだ\(posts.count)曲", "\(posts.count) songs from \(people) people"))
            .font(.subheadline)
            .foregroundColor(.dlTextSub)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.largeTitle).foregroundColor(.dlTextLight)
            Text(verbatim: S("この期間に選ばれた曲はまだありません", "No songs in this period yet"))
                .font(.subheadline).foregroundColor(.dlTextSub)
        }
        .frame(maxWidth: .infinity)
        .dlCard(padding: 32)
    }

    private func load() async {
        guard !locked else { posts = []; return }
        loading = true
        defer { loading = false }
        let found = await social.posts(from: range.start, to: range.end.addingTimeInterval(-1))
        guard !Task.isCancelled else { return }
        // 日付の古い順、同じ日は選んだ順
        posts = found.sorted { ($0.dayKey, $0.postedAt) < ($1.dayKey, $1.postedAt) }
    }

    private func shift(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: span.component, value: delta, to: anchor) { anchor = d }
    }
}

/// 「＜ 期間 ＞」の切り替え
struct PeriodHeader: View {
    let title: String
    var canGoForward = true
    let shift: (Int) -> Void

    var body: some View {
        HStack {
            arrow("chevron.left", enabled: true) { shift(-1) }
            Spacer()
            Text(verbatim: title).font(.headline).foregroundColor(.dlText)
            Spacer()
            arrow("chevron.right", enabled: canGoForward) { shift(1) }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundColor(.dlPrimary)
                .frame(width: 36, height: 36)
                .background(Color.dlPrimaryBg)
                .clipShape(Circle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
