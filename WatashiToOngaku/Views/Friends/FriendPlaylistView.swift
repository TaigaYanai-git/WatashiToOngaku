import MusicKit
import SwiftUI

/// フレンドが選んだ曲を、1週間・月・年のプレイリストにする（月・年は Plus）。
/// 選んでいるタイムラインのフレンドだけで作る
struct FriendPlaylistView: View {
    enum Span: String, CaseIterable, Identifiable {
        case week, month, year
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week: return S("1週間", "Week", "1주")
            case .month: return S("月", "Month", "월")
            case .year: return S("年", "Year", "년")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @ObservedObject private var timelineLists = TimelineListStore.shared
    @State private var span: Span = .week
    /// 月・年のどこを見ているか（その期間の中の日）
    @State private var anchor = Date()
    @State private var posts: [FriendPost] = []
    @State private var loading = false
    @State private var working: String?
    @State private var musicError: String?
    @State private var savedName: String?
    @State private var showOffer = false
    @State private var showPlus = false

    private var calendar: Calendar { .current }
    private var list: TimelineList? { timelineLists.current(isPlus: plus.isPlus) }
    private var locked: Bool { span != .week && !plus.isPlus }

    /// 期間の始まりと終わり
    private var range: (start: Date, end: Date) {
        switch span {
        case .week:
            return (calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date(), Date())
        case .month:
            let start = calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor
            return (start, calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start)
        case .year:
            let start = calendar.dateInterval(of: .year, for: anchor)?.start ?? anchor
            return (start, calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? start)
        }
    }

    private var periodTitle: String {
        switch span {
        case .week: return S("この1週間", "This Week", "이번 주")
        case .month: return anchor.formatted(.dateTime.locale(.app).year().month())
        case .year: return anchor.formatted(.dateTime.locale(.app).year())
        }
    }

    private var playlistName: String {
        let base = S("フレンドの曲 \(periodTitle)", "Friends' Songs \(periodTitle)", "친구의 곡 \(periodTitle)")
        return list.map { "\(base)（\($0.name)）" } ?? base
    }

    private var canGoForward: Bool { range.end < calendar.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("", selection: $span) {
                        ForEach(Span.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if span != .week { periodHeader }

                    if locked {
                        lockedCard
                    } else if loading {
                        ProgressView().tint(.dlPrimary).padding(40)
                    } else if posts.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note.list").font(.largeTitle).foregroundColor(.dlTextLight)
                            Text(verbatim: S("この期間のフレンドの曲はまだありません", "No songs from friends in this period", "이 기간의 친구 곡이 아직 없습니다"))
                                .font(.subheadline).foregroundColor(.dlTextSub)
                        }
                        .frame(maxWidth: .infinity)
                        .dlCard(padding: 32)
                    } else {
                        actions
                        songList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: list?.name ?? S("フレンドのプレイリスト", "Friends' Playlist", "친구 플레이리스트")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .task(id: "\(span.rawValue)-\(DayKey.string(from: range.start))-\(list?.id ?? "all")-\(plus.isPlus)") { await load() }
            .sheet(isPresented: $showPlus) { PlusView() }
            .alert(Text(verbatim: musicError ?? ""), isPresented: Binding(get: { musicError != nil }, set: { if !$0 { musicError = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .alert(Text(verbatim: S("「\(savedName ?? "")」をライブラリに保存しました", "Saved \"\(savedName ?? "")\" to your library", "'\(savedName ?? "")'을(를) 보관함에 저장했습니다")),
                   isPresented: Binding(get: { savedName != nil }, set: { if !$0 { savedName = nil } })) {
                Button(S("ミュージックで開く", "Open Music")) { AppleMusicService.openMusicApp() }
                Button("OK", role: .cancel) {}
            }
            .musicSubscriptionOffer(isPresented: $showOffer, options: MusicSubscriptionOffer.Options(messageIdentifier: .playMusic))
        }
    }

    private var periodHeader: some View {
        HStack {
            circleButton("chevron.left") { shift(-1) }
            Spacer()
            Text(verbatim: periodTitle).font(.headline).foregroundColor(.dlText)
            Spacer()
            circleButton("chevron.right") { shift(1) }
                .opacity(canGoForward ? 1 : 0.3)
                .disabled(!canGoForward)
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundColor(.dlPrimary)
                .frame(width: 36, height: 36)
                .background(Color.dlPrimaryBg)
                .clipShape(Circle())
        }
    }

    private func shift(_ value: Int) {
        let component: Calendar.Component = span == .year ? .year : .month
        anchor = calendar.date(byAdding: component, value: value, to: anchor) ?? anchor
    }

    private var lockedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(LinearGradient.dlPrimary)
            Text(verbatim: S("月・年のフレンドのプレイリストは Plus で使えます",
                             "Monthly and yearly friends' playlists are part of Plus",
                             "월·연 단위 친구 플레이리스트는 Plus에서 사용할 수 있습니다"))
                .font(.subheadline.weight(.semibold)).foregroundColor(.dlText).multilineTextAlignment(.center)
            Text(verbatim: S("1か月や1年のあいだにフレンドが選んだ曲を、まとめて聴けます",
                             "Listen to everything your friends picked over a month or a year",
                             "한 달, 1년 동안 친구들이 고른 곡을 한 번에 들을 수 있습니다"))
                .font(.caption).foregroundColor(.dlTextSub).multilineTextAlignment(.center)
            Button(S("Plus について見る", "Learn About Plus", "Plus 알아보기")) { showPlus = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .dlCard(padding: 24)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionButton(id: "order", label: S("上から再生", "Play", "재생")) { PlayFromTopIcon() } action: {
                try await AppleMusicService.play(posts.map(\.songID))
            }
            actionButton(id: "shuffle", label: S("シャッフル", "Shuffle", "셔플")) { Image(systemName: "shuffle") } action: {
                try await AppleMusicService.play(posts.map(\.songID), shuffle: true)
            }
            actionButton(id: "save", label: S("保存", "Save", "저장")) { Image(systemName: "plus.square.on.square") } action: {
                let name = playlistName
                try await AppleMusicService.save(posts.map(\.songID), name: name,
                                                 description: S("Our Music でフレンドが選んだ曲", "Songs picked by friends on Our Music", "Our Music에서 친구들이 고른 곡"),
                                                 key: "friends-\(list?.id ?? "all")-\(span.rawValue)-\(DayKey.string(from: range.start))")
                savedName = name
            }
        }
    }

    private func actionButton<Icon: View>(id: String, label: String, @ViewBuilder icon: () -> Icon,
                                          action: @escaping () async throws -> Void) -> some View {
        Button {
            working = id
            Task {
                defer { working = nil }
                do {
                    try await action()
                } catch AppleMusicService.Failure.noSubscription(let canSubscribe) where canSubscribe {
                    showOffer = true
                } catch {
                    musicError = error.localizedDescription
                }
            }
        } label: {
            VStack(spacing: 4) {
                if working == id { ProgressView().tint(.dlPrimary) } else { icon() }
                Text(verbatim: label).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.dlPrimaryBg)
            .cornerRadius(16)
        }
        .foregroundColor(.dlPrimary)
        .disabled(working != nil)
    }

    private var songList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(S("\(posts.count)曲", "\(posts.count) songs", "\(posts.count)곡"), systemImage: "music.note.list")
                .font(.subheadline.weight(.semibold)).foregroundColor(.dlTextSub)
            ForEach(posts) { post in
                HStack(spacing: 12) {
                    ArtworkView(url: post.artworkURL, cornerRadius: 8).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                        Text(verbatim: "\(post.artist) ・ \(post.friend.nickname)").font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
                    }
                    Spacer()
                    Text(verbatim: post.day?.formatted(.dateTime.locale(.app).month(.defaultDigits).day()) ?? "")
                        .font(.caption2).foregroundColor(.dlTextLight)
                }
            }
        }
        .dlCard()
    }

    private func load() async {
        guard !locked else { posts = []; return }
        loading = true
        defer { loading = false }
        let list = self.list
        let found = await social.posts(from: range.start, to: range.end, includeAllOfMine: false)
        // 古い日から順に（同じ日は投稿した順）
        posts = found.filter { TimelineListStore.includes($0, in: list) }.sorted {
            $0.dayKey != $1.dayKey ? $0.dayKey < $1.dayKey : $0.postedAt < $1.postedAt
        }
    }
}
