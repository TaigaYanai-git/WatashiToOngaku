import MusicKit
import SwiftUI

/// フレンドが選んだ曲が、新しい順に流れる
struct TimelineView: View {
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var adStore = NativeAdStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @ObservedObject private var timelineLists = TimelineListStore.shared
    @Environment(\.openURL) private var openURL
    @State private var showFriends = false
    @State private var showProfile = false
    @State private var showPlaylist = false
    @State private var showPlus = false
    @State private var reporting: FriendPost?
    /// タイムラインの曲を Apple Music で流している最中（"order" / "shuffle"）
    @State private var playing: String?
    @State private var playError: String?
    @State private var showOffer = false
    /// 再生ボタンで流し始めたら、流れている曲の投稿までスクロールして追いかける
    @State private var followsPlayback = false
    @ObservedObject private var musicQueue = SystemMusicPlayer.shared.queue
    @ObservedObject private var musicState = SystemMusicPlayer.shared.state

    var body: some View {
        NavigationStack {
            Group {
                switch social.state {
                case .notSetUp:
                    SocialSetupView()
                case .unavailable(let message):
                    message_(message)
                case .ready:
                    list
                }
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("タイムライン", "Timeline")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                if social.state == .ready {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { showProfile = true } label: {
                            AvatarView(code: social.friendCode, version: social.avatarVersion, nickname: social.nickname, size: 30)
                        }
                        .accessibilityLabel(S("プロフィール", "Profile"))
                    }
                    // 選んでいるタイムラインの1週間分の曲を、上から順に／シャッフルで Apple Music で聴く
                    ToolbarItem(placement: .navigationBarTrailing) {
                        playButton("order", label: S("1週間分を上から再生", "Play This Week in Order"))
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        playButton("shuffle", label: S("1週間分をシャッフル再生", "Shuffle This Week"))
                    }
                    // 週・月・年のフレンドのプレイリスト
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showPlaylist = true } label: { Image(systemName: "music.note.list") }
                            .foregroundColor(.dlPrimary)
                            .accessibilityLabel(S("フレンドのプレイリスト", "Friends' Playlist", "친구 플레이리스트"))
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showFriends = true } label: {
                            Image(systemName: "person.2.badge.plus")
                                // 届いたフレンド申請があれば印を付ける
                                .overlay(alignment: .topTrailing) {
                                    if !social.incomingRequests.isEmpty {
                                        Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: 3, y: -3)
                                    }
                                }
                        }
                        .foregroundColor(.dlPrimary)
                        .accessibilityLabel(S("フレンド", "Friends"))
                    }
                }
            }
            .sheet(isPresented: $showFriends) { FriendsView() }
            .sheet(isPresented: $showPlaylist) { FriendPlaylistView() }
            .sheet(isPresented: $showPlus) { PlusView() }
            .alert(Text(verbatim: playError ?? ""), isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .musicSubscriptionOffer(isPresented: $showOffer, options: MusicSubscriptionOffer.Options(messageIdentifier: .playMusic))
            .sheet(isPresented: $showProfile) {
                VStack(spacing: 20) {
                    Text(verbatim: S("プロフィール", "Profile")).font(.headline).foregroundColor(.dlText)
                    ProfileHeader(size: 110)
                    Button(S("閉じる", "Close")) { showProfile = false }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.horizontal, 60)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DlBackground().ignoresSafeArea())
                .presentationDetents([.medium])
            }
            .confirmationDialog(S("この投稿を通報しますか？", "Report this post?"),
                                isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                                titleVisibility: .visible, presenting: reporting) { post in
                ForEach([S("不適切な内容", "Inappropriate"), S("嫌がらせ・いじめ", "Harassment"), S("スパム", "Spam")], id: \.self) { reason in
                    Button(reason, role: .destructive) { Task { await social.report(post, reason: reason) } }
                }
            } message: { post in
                Text(verbatim: S("開発者に知らせ、\(post.friend.nickname)さんをブロックします。", "We'll notify the developer and block \(post.friend.nickname).", "개발자에게 알리고 \(post.friend.nickname)님을 차단합니다."))
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 6) {
            if !social.friends.isEmpty {
                TimelineListBar().padding(.top, 10)
            }
            LazyVStack(spacing: 14) {
                if posts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.wave.2").font(.largeTitle).foregroundColor(.dlTextLight)
                        Text(verbatim: social.friends.isEmpty
                             ? S("フレンドを追加すると、選んだ曲がここに流れます", "Add friends to see their songs here")
                             : selectedList != nil
                             ? S("このタイムラインの投稿はまだありません。長押しで入れるフレンドを編集できます", "No posts in this timeline yet. Long-press its name to edit friends.", "이 타임라인에는 아직 게시물이 없습니다. 이름을 길게 눌러 친구를 편집할 수 있습니다")
                             : S("フレンドの投稿はまだありません", "No posts from friends yet"))
                            .font(.subheadline)
                            .foregroundColor(.dlTextSub)
                            .multilineTextAlignment(.center)
                        if social.friends.isEmpty {
                            Button(S("フレンドを追加", "Add Friends")) { showFriends = true }
                                .buttonStyle(PrimaryButtonStyle())
                                .padding(.horizontal, 40)
                        }
                    }
                    .padding(.top, 60)
                }
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    PostCard(post: post, isPlaying: isNowPlaying(post)) { reporting = post }
                        .id(post.id)
                    // 投稿5件ごとに広告を挟む（Plus の人には出さない）
                    if (index + 1) % NativeAdStore.interval == 0, !plus.isPlus,
                       let ad = adStore.ad(forSlot: (index + 1) / NativeAdStore.interval - 1) {
                        NativeAdCard(ad: ad)
                    }
                }
                if !posts.isEmpty { loadMoreFooter }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            }
        }
        .refreshable { await social.refresh() }
        .task { await social.refresh() }
        .task(id: posts.count) { await adStore.load(forPosts: posts.count) }
        // タイムラインの曲が流れている（一時停止中も）あいだは、下に操作バーを出す
        .safeAreaInset(edge: .bottom) {
            if let post = currentPost, let song = currentSong {
                NowPlayingBar(artworkURL: post.artworkURL, title: post.title, subtitle: "\(post.artist) ・ \(post.friend.nickname)",
                              isPlaying: song.isPlaying) { followsPlayback = true }
            }
        }
        .onChange(of: currentSong) { _, _ in
            guard followsPlayback, let post = weekPosts.first(where: isNowPlaying) else { return }
            withAnimation { proxy.scrollTo(post.id, anchor: .center) }
        }
        }
    }

    /// タイムラインのいちばん下。Plus はさらに前の投稿を読み込める
    @ViewBuilder
    private var loadMoreFooter: some View {
        if social.canLoadMore {
            Button {
                Task { await social.loadMore() }
            } label: {
                if social.isLoadingMore {
                    ProgressView().tint(.dlPrimary)
                } else {
                    Text(verbatim: S("さらに前の投稿を読み込む", "Load Earlier Posts", "이전 게시물 더 보기"))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(social.isLoadingMore)
        } else if !plus.isPlus {
            Button { showPlus = true } label: {
                Label(S("Plus なら1年前まで遡れます", "Go back up to a year with Plus", "Plus로 1년 전까지 볼 수 있습니다"), systemImage: "sparkles")
            }
            .buttonStyle(SecondaryButtonStyle())
        } else {
            Text(verbatim: S("ここより前の投稿はありません", "No earlier posts", "더 이전 게시물이 없습니다"))
                .font(.caption).foregroundColor(.dlTextLight).padding(.vertical, 8)
        }
    }

    /// ミュージックの今の曲（一時停止中も含む）
    private var currentSong: NowPlayingSong? { NowPlayingSong.current(queue: musicQueue, state: musicState) }

    private func matches(_ post: FriendPost, _ song: NowPlayingSong?) -> Bool {
        song?.matches(songID: post.songID, title: post.title, artist: post.artist) ?? false
    }

    /// ミュージックで流れている曲（タイムラインの再生ボタンで流したものを、アプリ内でも分かるようにする）
    private func isNowPlaying(_ post: FriendPost) -> Bool {
        guard let song = currentSong, song.isPlaying else { return false }
        return matches(post, song)
    }

    /// 今の曲がタイムラインにあれば、その投稿
    private var currentPost: FriendPost? {
        guard let song = currentSong else { return nil }
        return posts.first { matches($0, song) }
    }

    /// 今日を含めた1週間（7日）の投稿。タイムラインと同じ並び
    private var weekPosts: [FriendPost] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        let firstKey = DayKey.string(from: start)
        return posts.filter { $0.dayKey >= firstKey }
    }

    /// 今選んでいるタイムライン（「みんな」なら nil）
    private var selectedList: TimelineList? { timelineLists.current(isPlus: plus.isPlus) }

    /// 選んでいるタイムラインに出す投稿
    private var posts: [FriendPost] {
        let list = selectedList
        return social.timeline.filter { TimelineListStore.includes($0, in: list) }
    }

    private func playButton(_ id: String, label: String) -> some View {
        Button { play(id) } label: {
            if playing == id {
                ProgressView().tint(.dlPrimary)
            } else if id == "order" {
                PlayFromTopIcon()
            } else {
                Image(systemName: "shuffle")
            }
        }
        .foregroundColor(.dlPrimary)
        .disabled(weekPosts.isEmpty || playing != nil)
        .accessibilityLabel(label)
    }

    private func play(_ id: String) {
        playing = id
        Task {
            defer { playing = nil }
            do {
                try await AppleMusicService.play(weekPosts.map(\.songID), shuffle: id == "shuffle")
                followsPlayback = true
            } catch AppleMusicService.Failure.noSubscription(let canSubscribe) where canSubscribe {
                showOffer = true
            } catch {
                playError = error.localizedDescription
            }
        }
    }

    private func message_(_ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash").font(.largeTitle).foregroundColor(.dlTextLight)
            Text(verbatim: text).font(.subheadline).foregroundColor(.dlTextSub).multilineTextAlignment(.center)
            Button(S("もう一度試す", "Try Again")) { Task { await social.start() } }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 60)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PostCard: View {
    let post: FriendPost
    /// ミュージックで今流れている曲
    var isPlaying = false
    let onReport: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AvatarView(code: post.friend.code, version: post.friend.avatarVersion, nickname: post.friend.nickname)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: post.friend.isMe ? S("\(post.friend.nickname)（あなた）", "\(post.friend.nickname) (you)", "\(post.friend.nickname) (나)") : post.friend.nickname)
                        .font(.subheadline.weight(.semibold)).foregroundColor(.dlText)
                    Text(verbatim: dayText).font(.caption).foregroundColor(.dlTextSub)
                }
                Spacer()
                if isPlaying {
                    NowPlayingBadge()
                } else {
                    Text(post.postedAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.dlTextLight)
                }
                Menu {
                    if let link = post.appleMusicURL.flatMap(URL.init(string:)) {
                        Button(S("Apple Musicで聴く", "Open in Apple Music"), systemImage: "music.note") { openURL(link) }
                    }
                    if !post.friend.isMe {
                        Button(S("通報してブロック", "Report & Block"), systemImage: "exclamationmark.bubble", role: .destructive, action: onReport)
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundColor(.dlTextSub).frame(width: 30, height: 30)
                }
            }
            HStack(spacing: 14) {
                PlayableArtwork(id: post.id, artworkURL: post.artworkURL, previewURL: post.previewURL,
                                size: 88, cornerRadius: 12, songID: post.songID, clipStart: post.clipStart)
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.title).font(.headline).foregroundColor(.dlText).lineLimit(2)
                    Text(post.artist).font(.subheadline).foregroundColor(.dlTextSub).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if !post.memo.isEmpty {
                Text(post.memo)
                    .font(.subheadline)
                    .foregroundColor(.dlText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dlCardTint)
                    .cornerRadius(12)
            }
        }
        .dlCard()
        .overlay {
            if isPlaying {
                RoundedRectangle(cornerRadius: 20).stroke(LinearGradient.dlPrimary, lineWidth: 2.5)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
    }

    private var dayText: String {
        guard let day = post.day else { return "" }
        return S("\(day.formatted(.dateTime.locale(.app).month().day()))の一曲", "Song of \(day.formatted(.dateTime.locale(.app).month().day()))", "\(day.formatted(.dateTime.locale(.app).month().day()))의 한 곡")
    }
}

/// フレンド機能をはじめる：ニックネームとルールへの同意
struct SocialSetupView: View {
    @ObservedObject private var social = SocialStore.shared
    @State private var nickname = ""
    @State private var agreed = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient.dlPrimary)
                    .padding(.top, 24)
                Text(verbatim: S("フレンドと今日の一曲を共有しよう", "Share your daily song with friends"))
                    .font(.title3.weight(.bold))
                    .foregroundColor(.dlText)
                    .multilineTextAlignment(.center)
                Text(verbatim: S("あなたの曲は、お互いに承認したフレンドだけに見えます。日ごとに「共有しない」「メモは見せない」も選べます。",
                                 "Only friends you accept can see your songs. You can hide a day or its note anytime."))
                    .font(.subheadline)
                    .foregroundColor(.dlTextSub)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: S("ニックネーム", "Nickname")).font(.caption.weight(.semibold)).foregroundColor(.dlTextSub)
                    TextField(S("フレンドに表示される名前", "Name shown to friends"), text: $nickname)
                        .textFieldStyle(DarkTextFieldStyle())
                }
                .dlCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: S("みんなが気持ちよく使うためのルール", "Community rules"))
                        .font(.subheadline.weight(.semibold)).foregroundColor(.dlText)
                    Text(verbatim: S("・他の人を傷つける内容、差別的・性的・暴力的な内容は投稿しないでください。\n・不適切な投稿は「通報してブロック」で知らせることができます。開発者が確認し、ルールに反する利用者は利用できなくなることがあります。",
                                     "• Don't post hurtful, discriminatory, sexual, or violent content.\n• You can report and block inappropriate posts. The developer reviews reports and may remove users who break the rules."))
                        .font(.caption)
                        .foregroundColor(.dlTextSub)
                    Toggle(S("ルールに同意する", "I agree to the rules"), isOn: $agreed)
                        .font(.subheadline)
                        .tint(.dlPrimary)
                }
                .dlCard()

                Button {
                    working = true
                    Task {
                        await social.setUp(nickname: nickname.trimmingCharacters(in: .whitespaces))
                        working = false
                    }
                } label: {
                    if working { ProgressView().tint(.white) } else { Text(verbatim: S("はじめる", "Get Started")) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty || !agreed || working)
            }
            .padding(20)
        }
    }
}
