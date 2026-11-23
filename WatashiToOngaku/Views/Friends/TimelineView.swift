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
    @State private var previewComments: FriendPost?
    @State private var previewProfile: Friend?
    @State private var showProfile = false
    @State private var showPlaylist = false
    @State private var showPlus = false
    @State private var reporting: FriendPost?
    /// タイムラインの曲を Apple Music で流している最中（"order" / "shuffle"）
    @State private var playing: String?
    @State private var playError: String?
    @State private var showOffer = false
    @State private var bulkRequest: SpotifyBulkRequest?
    /// 再生ボタンで流し始めたら、流れている曲の投稿までスクロールして追いかける
    @State private var followsPlayback = false
    /// 流れている曲の投稿（今のページがここまでスクロールする）
    @State private var scrollTarget: String?
    /// 横にめくっている途中の位置（0 =「みんな」、1 = 1つ目のタイムライン…）。タブの下線を指に合わせて動かす
    @State private var pageProgress: CGFloat = 0
    @ObservedObject private var musicQueue = SystemMusicPlayer.shared.queue
    @ObservedObject private var musicState = SystemMusicPlayer.shared.state

    var body: some View {
        NavigationStack {
            Group {
                switch social.state {
                case .notSetUp:
                    SocialSetupView()
                case .connecting:
                    SpinningDisc()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .tourTarget(.timelineOrder)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        playButton("shuffle", label: S("1週間分をシャッフル再生", "Shuffle This Week"))
                            .tourTarget(.timelineShuffle)
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
                        .tourTarget(.addFriend)
                    }
                }
            }
            .sheet(isPresented: $showFriends) { FriendsView() }
            .sheet(item: $previewComments) { CommentsSheet(post: $0) }
            .sheet(item: $previewProfile) { FriendProfileSheet(friend: $0) }
            // スクリーンショット用：-uiPreview -previewSheet friends|comments で画面を開く
            .task {
                guard social.isPreview else { return }
                try? await Task.sleep(for: .milliseconds(600))
                switch UserDefaults.standard.string(forKey: "previewSheet") {
                case "friends": showFriends = true
                case "comments": previewComments = social.timeline.first
                case "friendComments": previewComments = social.timeline.first { !$0.friend.isMe }
                case "profile": previewProfile = social.friends.first
                default: break
                }
            }
            .sheet(isPresented: $showPlaylist) { FriendPlaylistView() }
            .sheet(isPresented: $showPlus) { PlusView() }
            .alert(Text(verbatim: playError ?? ""), isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .musicSubscriptionOffer(isPresented: $showOffer, options: MusicSubscriptionOffer.Options(messageIdentifier: .playMusic))
            .spotifyBulkNotice($bulkRequest)
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

    /// 「みんな」と、作ったタイムラインのページの ID（左から順）
    private var pageIDs: [String] {
        [TimelineListStore.allID] + timelineLists.available(isPlus: plus.isPlus).map(\.id)
    }

    private var currentPageID: String { selectedList?.id ?? TimelineListStore.allID }

    private var list: some View {
        VStack(spacing: 0) {
            if !social.friends.isEmpty {
                TimelineGroupTabs(progress: pageProgress)
            }
            pager
        }
        .task { await social.refresh() }
        // タイムラインの曲が流れている（一時停止中も）あいだは、下に操作バーを出す
        .safeAreaInset(edge: .bottom) {
            if let post = currentPost, let song = currentSong {
                NowPlayingBar(artworkURL: post.artworkURL, title: post.title, subtitle: "\(post.artist) ・ \(post.friend.nickname)",
                              isPlaying: song.isPlaying) { followsPlayback = true }
            }
        }
        .onChange(of: currentSong) { _, _ in
            guard followsPlayback, let post = weekPosts.first(where: isNowPlaying) else { return }
            scrollTarget = post.id
        }
        // 横にめくってタイムラインが変わったら、軽く震わせる
        .sensoryFeedback(.selection, trigger: currentPageID)
    }

    /// タイムラインを左右にめくって切り替える
    private var pager: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pageIDs, id: \.self) { id in
                        TimelinePage(list: timelineLists.available(isPlus: plus.isPlus).first { $0.id == id },
                                     isCurrent: id == currentPageID,
                                     scrollTarget: scrollTarget,
                                     isNowPlaying: isNowPlaying,
                                     onReport: { reporting = $0 },
                                     onAddFriends: { showFriends = true },
                                     onPlus: { showPlus = true })
                            .frame(width: width)
                            // 指の動きに合わせて、上のタブの下線を動かす
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("timelinePager")).minX } action: { x in
                                guard let index = pageIDs.firstIndex(of: id), x <= 0.5, x > -width else { return }
                                pageProgress = CGFloat(index) - x / width
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .coordinateSpace(name: "timelinePager")
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: Binding(
                get: { currentPageID },
                set: { if let id = $0 { timelineLists.selectedID = id } }
            ))
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
        Button { SpotifyBulkRequest.run(pending: $bulkRequest) { play(id) } } label: {
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

/// 1つのタイムライン（「みんな」か、作ったタイムライン）の投稿を縦に並べる
private struct TimelinePage: View {
    /// nil なら「みんな」
    let list: TimelineList?
    /// いま表示しているページか（広告と、再生中の曲への追いかけはこのページだけ）
    let isCurrent: Bool
    let scrollTarget: String?
    let isNowPlaying: (FriendPost) -> Bool
    let onReport: (FriendPost) -> Void
    let onAddFriends: () -> Void
    let onPlus: () -> Void
    @ObservedObject private var social = SocialStore.shared
    @ObservedObject private var adStore = NativeAdStore.shared
    @ObservedObject private var plus = PlusStore.shared

    private var posts: [FriendPost] { social.timeline.filter { TimelineListStore.includes($0, in: list) } }

    var body: some View {
        let posts = posts
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if !social.friends.isEmpty {
                        TimelineMembersRow(list: list)
                    }
                    if posts.isEmpty {
                        emptyState
                    }
                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                        PostCard(post: post, isPlaying: isNowPlaying(post)) { onReport(post) }
                            .id(post.id)
                        // 投稿5件ごとに広告を挟む（Plus の人には出さない）。1つの広告は1か所にしか出せないので、表示中のページだけ
                        if isCurrent, (index + 1) % NativeAdStore.interval == 0, !plus.isPlus,
                           let ad = adStore.ad(forSlot: (index + 1) / NativeAdStore.interval - 1) {
                            NativeAdCard(ad: ad)
                        }
                    }
                    if !posts.isEmpty { loadMoreFooter }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .refreshable { await social.refresh() }
            .task(id: isCurrent ? posts.count : -1) {
                if isCurrent { await adStore.load(forPosts: posts.count) }
            }
            .onChange(of: scrollTarget) { _, id in
                guard isCurrent, let id, posts.contains(where: { $0.id == id }) else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2").font(.largeTitle).foregroundColor(.dlTextLight)
            Text(verbatim: social.friends.isEmpty
                 ? S("フレンドを追加すると、選んだ曲がここに流れます", "Add friends to see their songs here")
                 : list != nil
                 ? S("このタイムラインの投稿はまだありません", "No posts in this timeline yet", "이 타임라인에는 아직 게시물이 없습니다")
                 : S("フレンドの投稿はまだありません", "No posts from friends yet"))
                .font(.subheadline)
                .foregroundColor(.dlTextSub)
                .multilineTextAlignment(.center)
            if social.friends.isEmpty {
                Button(S("フレンドを追加", "Add Friends")) { onAddFriends() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 40)
            }
        }
        .padding(.top, 60)
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
            Button { onPlus() } label: {
                Label(S("Plus なら1年前まで遡れます", "Go back up to a year with Plus", "Plus로 1년 전까지 볼 수 있습니다"), systemImage: "sparkles")
            }
            .buttonStyle(SecondaryButtonStyle())
        } else {
            Text(verbatim: S("ここより前の投稿はありません", "No earlier posts", "더 이전 게시물이 없습니다"))
                .font(.caption).foregroundColor(.dlTextLight).padding(.vertical, 8)
        }
    }
}

private struct PostCard: View {
    let post: FriendPost
    /// ミュージックで今流れている曲
    var isPlaying = false
    let onReport: () -> Void
    @ObservedObject private var social = SocialStore.shared
    @State private var showComments = false
    @State private var showProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // フレンドのアイコンを押すと、その人のプロフィールとフレンドの一覧
                // 自分の投稿はボタンにしない（disabled にするとアイコンが薄く表示されるため）
                if post.friend.isMe {
                    AvatarView(friend: post.friend)
                } else {
                    Button { showProfile = true } label: { AvatarView(friend: post.friend) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(S("\(post.friend.nickname)さんのプロフィール", "\(post.friend.nickname)'s profile", "\(post.friend.nickname)님의 프로필"))
                }
                VStack(alignment: .leading, spacing: 1) {
                    // 名前は1行。長ければ末尾を省き、「（あなた）」や印は残す
                    HStack(spacing: 4) {
                        Text(verbatim: post.friend.nickname)
                            .font(.subheadline.weight(.semibold)).foregroundColor(.dlText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if post.friend.isMe {
                            Text(verbatim: S("（あなた）", "(you)", "(나)"))
                                .font(.subheadline.weight(.semibold)).foregroundColor(.dlText)
                                .fixedSize()
                        }
                    }
                    // 日付と、いつ選んだか（「2時間前」）。流れている曲なら印
                    HStack(spacing: 6) {
                        Text(verbatim: "\(dayText) ・ \(post.postedAt.formatted(.relative(presentation: .named).locale(.app)))")
                            .font(.caption).foregroundColor(.dlTextSub)
                            .lineLimit(1)
                        if isPlaying { NowPlayingBadge() }
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    ListenMenuItems(title: post.title, artist: post.artist, appleMusicURL: post.appleMusicURL)
                    if !post.friend.isMe {
                        Button(S("通報してブロック", "Report & Block"), systemImage: "exclamationmark.bubble", role: .destructive, action: onReport)
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundColor(.dlTextSub).frame(width: 30, height: 30)
                }
            }
            HStack(spacing: 14) {
                PlayableArtwork(id: post.id, artworkURL: post.artworkURL, previewURL: post.previewURL,
                                size: Self.artworkSize, cornerRadius: 12, songID: post.songID, clipStart: post.clipStart)
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.title).font(.headline).foregroundColor(.dlText).lineLimit(2)
                    Text(post.artist).font(.subheadline).foregroundColor(.dlTextSub).lineLimit(1)
                }
                Spacer(minLength: 0)
                // 黄金比：ハートの中心を、ジャケットの上から 1/φ（約 61.8%）の高さに置く
                likeButton
                    .padding(.top, Self.artworkSize / Self.goldenRatio - Self.heartBox / 2)
                    .frame(height: Self.artworkSize, alignment: .top)
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
            if post.friend.isMe, !likers.isEmpty {
                Text(verbatim: likersText)
                    .font(.caption)
                    .foregroundColor(.dlTextSub)
            }
            if social.canComment(on: post) { commentRow }
        }
        .dlCard()
        .sheet(isPresented: $showComments) { CommentsSheet(post: post) }
        .sheet(isPresented: $showProfile) { FriendProfileSheet(friend: post.friend) }
        // 画面に出たら、この投稿のいいねを読む（タイムラインを更新したら読み直す）
        .task(id: "\(post.id)#\(social.likesGeneration)") { social.requestLikes(for: post) }
        .overlay {
            if isPlaying {
                RoundedRectangle(cornerRadius: 20).stroke(LinearGradient.dlPrimary, lineWidth: 2.5)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
    }

    private var likers: [Friend] { social.likers[post.dayKey] ?? [] }

    private var comments: [PostComment] { social.comments[post.id] ?? [] }

    /// 新しいコメント2件と、コメントの画面への入口。どこを押してもコメントの画面を開く
    private var commentRow: some View {
        Button { showComments = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(comments.suffix(2)) { comment in
                    (Text(verbatim: comment.isMine ? S("あなた", "You", "나") : comment.nickname)
                        .font(.caption.weight(.semibold)).foregroundColor(.dlText)
                     + Text(verbatim: "  " + comment.text).font(.caption).foregroundColor(.dlText))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                    Text(verbatim: comments.count > 2
                         ? S("コメント\(comments.count)件をすべて見る", "View all \(comments.count) comments", "댓글 \(comments.count)개 모두 보기")
                         : comments.isEmpty ? S("コメントする", "Add a comment", "댓글 달기")
                         : S("返信する", "Reply", "답글 달기"))
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.dlTextSub)
            }
            .padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(S("コメント \(comments.count)件", "\(comments.count) comments", "댓글 \(comments.count)개"))
    }

    private static let artworkSize: CGFloat = 88
    private static let goldenRatio: CGFloat = 1.618
    /// ハートを押せる範囲
    private static let heartBox: CGFloat = 36
    private static let heartSize: CGFloat = 17

    /// フレンドの投稿にはいいねのボタン、自分の投稿にはいいねの数
    @ViewBuilder
    private var likeButton: some View {
        if post.friend.isMe {
            if !likers.isEmpty {
                VStack(spacing: -6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: Self.heartSize))
                        .foregroundColor(.pink)
                        .frame(width: Self.heartBox, height: Self.heartBox)
                    Text(verbatim: likeCountText).font(.caption2.weight(.semibold)).foregroundColor(.dlTextSub)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(S("いいね \(likeCountText)件", "\(likeCountText) likes", "좋아요 \(likeCountText)개"))
            }
        } else {
            LikeButton(liked: social.likedByMe.contains(post.id), size: Self.heartSize, box: Self.heartBox) {
                Task { await social.toggleLike(post) }
            }
        }
    }

    private var likeCountText: String { "\(likers.count)" }

    /// 「Mioさん、Kenさんがいいねしました」。4人以上なら「Mioさん、Kenさん、Yuiさんほか5人」
    private var likersText: String {
        let shown = likers.prefix(3).map(\.nickname)
        let rest = likers.count - shown.count
        let more = ""
        return S("\(shown.map { $0 + "さん" }.joined(separator: "、"))\(rest > 0 ? "ほか\(rest)\(more)人" : "")がいいねしました",
                 "Liked by \(shown.joined(separator: ", "))\(rest > 0 ? " and \(rest)\(more) others" : "")",
                 "\(shown.map { $0 + "님" }.joined(separator: ", "))\(rest > 0 ? " 외 \(rest)\(more)명" : "")이 좋아요를 눌렀습니다")
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
                .tourTarget(.socialSetup)

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

/// いいねのハート。押すと一度縮んでから弾むように大きくなり、まわりに粒がはじける。
/// 押したとき・取り消したときで手ごたえ（振動）を変える
private struct LikeButton: View {
    let liked: Bool
    let size: CGFloat
    let box: CGFloat
    let action: () -> Void
    /// いいねするたびに増やして、弾む動きと粒をもう一度動かす
    @State private var pops = 0

    var body: some View {
        Button {
            if !liked { pops += 1 }
            action()
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(liked ? Color.pink : Color.dlTextSub)
                .contentTransition(.symbolEffect(.replace))
                .keyframeAnimator(initialValue: 1.0, trigger: pops) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    // 縮む → 大きく弾む → 少し戻って落ち着く
                    CubicKeyframe(0.7, duration: 0.08)
                    SpringKeyframe(1.35, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.35, spring: .bouncy(extraBounce: 0.2))
                }
                .background { LikeBurst(trigger: pops, radius: box * 0.62) }
                .frame(width: box, height: box)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .sensoryFeedback(trigger: liked) { _, new in
            new ? .impact(weight: .medium, intensity: 0.9) : .impact(weight: .light, intensity: 0.5)
        }
        .accessibilityLabel(liked ? S("いいねを取り消す", "Unlike", "좋아요 취소") : S("いいね", "Like", "좋아요"))
    }
}

/// いいねしたときに、ハートのまわりへ広がって消える小さな粒
private struct LikeBurst: View {
    let trigger: Int
    let radius: CGFloat
    private static let count = 7

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { index in
                let angle = Double(index) / Double(Self.count) * 2 * .pi - .pi / 2
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.pink : Color.pink.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .keyframeAnimator(initialValue: BurstFrame(), trigger: trigger) { view, frame in
                        view
                            .scaleEffect(frame.scale)
                            .opacity(frame.opacity)
                            .offset(x: cos(angle) * radius * frame.distance, y: sin(angle) * radius * frame.distance)
                    } keyframes: { _ in
                        KeyframeTrack(\.distance) {
                            LinearKeyframe(0.35, duration: 0.06)
                            CubicKeyframe(1.0, duration: 0.32)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.06)
                            LinearKeyframe(1, duration: 0.14)
                            CubicKeyframe(0, duration: 0.2)
                        }
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(1, duration: 0.2)
                            CubicKeyframe(0.3, duration: 0.2)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct BurstFrame {
    var distance: CGFloat = 0.35
    /// 押す前は見えない
    var opacity: Double = 0
    var scale: CGFloat = 1
}

/// 指を置いたあいだ少し沈む
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
