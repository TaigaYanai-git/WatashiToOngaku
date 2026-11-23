import SwiftUI

/// 投稿へのコメント。
/// 上に投稿（ジャケットを押すと試聴できる）、まん中にコメント、下に入力欄。
/// 返信は返信先のコメントの下に字下げして並べ、誰への返信かを添える。長押しでコピー・削除・通報
struct CommentsSheet: View {
    let post: FriendPost
    @ObservedObject private var social = SocialStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sending = false
    @State private var loading = true
    @State private var reporting: PostComment?
    @State private var deleting: PostComment?
    @State private var message: String?
    /// 返信しようとしているコメント
    @State private var replyingTo: PostComment?
    @FocusState private var focused: Bool

    private var comments: [PostComment] { social.comments[post.id] ?? [] }
    private static let bottomID = "bottom"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        postHeader
                            .padding(.bottom, 18)
                        if comments.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                ForEach(CommentThread.threads(comments)) { thread in
                                    VStack(alignment: .leading, spacing: 12) {
                                        row(thread.root, replyingToName: nil)
                                        // 返信は字下げし、左に線を引いてつながりを見せる
                                        if !thread.replies.isEmpty {
                                            VStack(alignment: .leading, spacing: 12) {
                                                ForEach(thread.replies) { reply in
                                                    row(reply, replyingToName: thread.name(of: reply.replyTo))
                                                }
                                            }
                                            .padding(.leading, 14)
                                            .overlay(alignment: .leading) {
                                                Capsule().fill(Color.dlTextLight.opacity(0.35)).frame(width: 2)
                                            }
                                            .padding(.leading, 17)
                                        }
                                    }
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: comments.count) { _, _ in
                    withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                }
                .task {
                    await social.fetchComments(for: [post])
                    await social.fetchReactions(for: post)
                    loading = false
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: comments.isEmpty
                                  ? S("コメント", "Comments", "댓글")
                                  : S("コメント \(comments.count)件", "Comments (\(comments.count))", "댓글 \(comments.count)개")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .refreshable {
                await social.fetchComments(for: [post])
                await social.fetchReactions(for: post)
            }
            .confirmationDialog(S("このコメントを通報しますか？", "Report this comment?", "이 댓글을 신고할까요?"),
                                isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                                titleVisibility: .visible, presenting: reporting) { comment in
                ForEach([S("不適切な内容", "Inappropriate"), S("嫌がらせ・いじめ", "Harassment"), S("スパム", "Spam")], id: \.self) { reason in
                    Button(reason, role: .destructive) { Task { await social.report(comment, on: post, reason: reason) } }
                }
            } message: { comment in
                Text(verbatim: S("開発者に知らせ、\(comment.nickname)さんをブロックします。",
                                 "We'll notify the developer and block \(comment.nickname).",
                                 "개발자에게 알리고 \(comment.nickname)님을 차단합니다."))
            }
            .confirmationDialog(Text(verbatim: deleting.map { $0.isMine ? S("コメントを削除しますか？", "Delete this comment?", "댓글을 삭제할까요?")
                                                                   : S("このコメントを投稿から削除しますか？", "Remove this comment from your post?", "이 댓글을 게시물에서 삭제할까요?") } ?? ""),
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { comment in
                Button(S("削除", "Delete", "삭제"), role: .destructive) { Task { await social.deleteComment(comment, on: post) } }
            }
            .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ comment: PostComment, replyingToName: String?) -> some View {
        CommentRow(comment: comment,
                   reactions: social.commentReactions[comment.id] ?? [],
                   onReact: { emoji in Task { await social.react(emoji, to: comment, on: post) } },
                   replyingToName: replyingToName,
                   isPostOwner: post.friend.isMe,
                   isReplyTarget: replyingTo?.id == comment.id,
                   onReply: { reply(to: comment) },
                   onDelete: { deleting = comment },
                   onReport: { reporting = comment })
            .id(comment.id)
    }

    // MARK: - 投稿

    /// どの投稿へのコメントか。ジャケットを押すと試聴できる。メモがあれば添える
    private var postHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AvatarView(friend: post.friend, size: 26)
                Text(verbatim: post.friend.isMe ? S("あなたの一曲", "Your song", "나의 한 곡") : S("\(post.friend.nickname)さんの一曲", "\(post.friend.nickname)'s song", "\(post.friend.nickname)님의 한 곡"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.dlText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let day = post.day {
                    Text(verbatim: day.formatted(.dateTime.locale(.app).month().day()))
                        .font(.caption)
                        .foregroundColor(.dlTextSub)
                }
            }
            HStack(spacing: 14) {
                PlayableArtwork(id: post.id, artworkURL: post.artworkURL, previewURL: post.previewURL,
                                size: 64, cornerRadius: 10, songID: post.songID, clipStart: post.clipStart)
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.title).font(.headline).foregroundColor(.dlText).lineLimit(2)
                    Text(post.artist).font(.subheadline).foregroundColor(.dlTextSub).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if !post.memo.isEmpty {
                Text(post.memo)
                    .font(.subheadline)
                    .foregroundColor(.dlText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dlCardTint)
                    .cornerRadius(10)
            }
        }
        .dlCard()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if loading {
                ProgressView().tint(.dlPrimary)
            } else {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 34))
                    .foregroundStyle(LinearGradient.dlPrimary)
                Text(verbatim: S("最初のコメントを書いてみよう", "Be the first to comment", "첫 댓글을 남겨 보세요"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.dlText)
                if post.friend.isMe {
                    Text(verbatim: S("フレンドからのコメントがここに届きます", "Comments from friends will appear here", "친구의 댓글이 여기에 표시됩니다"))
                        .font(.caption)
                        .foregroundColor(.dlTextSub)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - 入力欄

    private var composer: some View {
        VStack(spacing: 8) {
            // 返信中なら、誰に返信しているかを出す（✕で取りやめ）
            if let target = replyingTo {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.caption2)
                    Text(verbatim: target.isMine ? S("自分のコメントに返信", "Replying to yourself", "내 댓글에 답글")
                         : S("\(target.nickname)さんに返信", "Replying to \(target.nickname)", "\(target.nickname)님에게 답글"))
                        .font(.caption.weight(.semibold))
                    Text(verbatim: target.text).font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { replyingTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.dlTextLight)
                    }
                    .accessibilityLabel(S("返信をやめる", "Cancel reply", "답글 취소"))
                }
                .foregroundColor(.dlPrimary)
                .padding(.horizontal, 20)
            }
            HStack(alignment: .bottom, spacing: 10) {
                AvatarView(code: social.friendCode, version: social.avatarVersion, nickname: social.nickname, size: 34)
                HStack(alignment: .bottom, spacing: 6) {
                    TextField(placeholder, text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($focused)
                        .font(.subheadline)
                        .foregroundColor(.dlText)
                        .padding(.vertical, 9)
                        .onChange(of: draft) { _, text in
                            if text.count > SocialStore.commentMaxLength { draft = String(text.prefix(SocialStore.commentMaxLength)) }
                        }
                    sendButton
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.dlCard))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(focused ? Color.dlPrimary.opacity(0.5) : Color.dlTextLight.opacity(0.3), lineWidth: 1))
            }
            .padding(.horizontal, 16)
            // 残りが少なくなったら文字数を出す
            if draft.count > SocialStore.commentMaxLength - 50 {
                Text(verbatim: "\(draft.count) / \(SocialStore.commentMaxLength)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(draft.count >= SocialStore.commentMaxLength ? .red : .dlTextSub)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var placeholder: String {
        if let target = replyingTo {
            return target.isMine ? S("返信を書く", "Write a reply", "답글 쓰기")
                : S("\(target.nickname)さんに返信", "Reply to \(target.nickname)", "\(target.nickname)님에게 답글")
        }
        return post.friend.isMe
            ? S("自分の曲にコメント", "Comment on your song", "내 곡에 댓글 달기")
            : S("\(post.friend.nickname)さんの曲にコメント", "Comment on \(post.friend.nickname)'s song", "\(post.friend.nickname)님의 곡에 댓글 달기")
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    private var sendButton: some View {
        Button(action: send) {
            Group {
                if sending {
                    ProgressView().tint(.dlPrimary)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 30, height: 30)
            .background(Circle().fill(canSend ? AnyShapeStyle(LinearGradient.dlPrimary) : AnyShapeStyle(Color.dlTextLight.opacity(0.4))))
            .padding(.bottom, 4)
        }
        .disabled(!canSend)
        .sensoryFeedback(.success, trigger: comments.count) { old, new in new > old }
        .accessibilityLabel(S("送信", "Send", "보내기"))
    }

    private func send() {
        let text = draft
        sending = true
        Task {
            if await social.postComment(text, on: post, replyTo: replyingTo) {
                draft = ""
                replyingTo = nil
            } else {
                message = social.lastError ?? S("コメントを送れませんでした", "Couldn't post your comment", "댓글을 보내지 못했습니다")
            }
            sending = false
        }
    }

    /// 返信：返信先を決めて書き始める
    private func reply(to comment: PostComment) {
        replyingTo = comment
        focused = true
    }
}

/// コメント1件。自分のコメントは少し色を付ける。長押しでコピー・削除・通報
private struct CommentRow: View {
    let comment: PostComment
    /// このコメントに付いた絵文字のリアクション
    let reactions: [CommentReaction]
    let onReact: (String) -> Void
    /// 返信なら返信先の人の名前
    let replyingToName: String?
    let isPostOwner: Bool
    /// いま返信しようとしているコメント（枠を付ける）
    let isReplyTarget: Bool
    let onReply: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    @State private var showsPicker = false

    /// 自分のコメントにはリアクションしない
    private var canReact: Bool { !comment.isMine }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(code: comment.code, version: comment.avatarVersion, nickname: comment.nickname,
                       size: replyingToName == nil ? 36 : 28)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(verbatim: comment.isMine ? S("あなた", "You", "나") : comment.nickname)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.dlText)
                            .lineLimit(1)
                        // 誰への返信か
                        if let name = replyingToName {
                            Image(systemName: "arrowtriangle.right.fill").font(.system(size: 6)).foregroundColor(.dlTextLight)
                            Text(verbatim: name)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.dlPrimary)
                                .lineLimit(1)
                        }
                    }
                    Text(comment.text)
                        .font(.subheadline)
                        .foregroundColor(.dlText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(comment.isMine ? Color.dlPrimaryBg : Color.dlCard))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.dlPrimary, lineWidth: isReplyTarget ? 1.5 : 0))
                .contextMenu { menu }
                // 2回すばやく押すと ❤️
                .onTapGesture(count: 2) { if canReact { onReact("❤️") } }
                if !reactions.isEmpty { reactionChips }
                HStack(spacing: 14) {
                    Text(verbatim: comment.postedAt.formatted(.relative(presentation: .named).locale(.app)))
                    Button(S("返信", "Reply", "답글"), action: onReply)
                        .fontWeight(.semibold)
                    if canReact {
                        Button { showsPicker = true } label: {
                            Image(systemName: "face.smiling")
                                .font(.subheadline)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "plus").font(.system(size: 7, weight: .heavy)).offset(x: 3, y: 1)
                                }
                        }
                        .accessibilityLabel(S("リアクション", "React", "반응"))
                        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
                            emojiPicker.presentationCompactAdaptation(.popover)
                        }
                    }
                    if comment.isMine {
                        Button(S("削除", "Delete", "삭제"), action: onDelete)
                    }
                }
                .font(.caption)
                .foregroundColor(.dlTextSub)
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
            Spacer(minLength: 24)
        }
    }

    /// 絵文字ごとの数。自分が付けた絵文字は色付き。押すと自分のリアクションを付ける／取り消す。長押しで誰が付けたか
    private var reactionChips: some View {
        let groups = Dictionary(grouping: reactions, by: \.emoji)
        let emojis = SocialStore.reactionEmojis.filter { groups[$0] != nil }
        return HStack(spacing: 6) {
            ForEach(emojis, id: \.self) { emoji in
                let people = groups[emoji] ?? []
                let mine = people.contains(where: \.isMine)
                Button { if canReact { onReact(emoji) } } label: {
                    HStack(spacing: 3) {
                        Text(verbatim: emoji).font(.caption)
                        Text(verbatim: "\(people.count)").font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundColor(mine ? .dlPrimary : .dlTextSub)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(mine ? Color.dlPrimaryBg : Color.dlCard))
                    .overlay(Capsule().stroke(mine ? Color.dlPrimary.opacity(0.6) : Color.dlTextLight.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ForEach(people) { person in
                        Text(verbatim: person.isMine ? S("あなた", "You", "나") : person.nickname)
                    }
                }
                .accessibilityLabel(Text(verbatim: "\(emoji) \(people.map { $0.isMine ? S("あなた", "You", "나") : $0.nickname }.joined(separator: ", "))"))
            }
        }
        .padding(.leading, 6)
        .animation(.snappy, value: reactions)
    }

    /// リアクションの絵文字を選ぶ
    private var emojiPicker: some View {
        let mine = reactions.first(where: \.isMine)?.emoji
        return HStack(spacing: 4) {
            ForEach(SocialStore.reactionEmojis, id: \.self) { emoji in
                Button {
                    showsPicker = false
                    onReact(emoji)
                } label: {
                    Text(verbatim: emoji)
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(mine == emoji ? Color.dlPrimaryBg : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: showsPicker)
    }

    @ViewBuilder
    private var menu: some View {
        Button(S("コピー", "Copy", "복사"), systemImage: "doc.on.doc") { UIPasteboard.general.string = comment.text }
        Button(S("返信", "Reply", "답글"), systemImage: "arrowshape.turn.up.left", action: onReply)
        if comment.isMine {
            Button(S("削除", "Delete", "삭제"), systemImage: "trash", role: .destructive, action: onDelete)
        } else {
            // 自分の投稿に付いたコメントは、ほかの人にも見えないようにできる
            if isPostOwner {
                Button(S("この投稿から削除", "Remove from My Post", "내 게시물에서 삭제"), systemImage: "eye.slash", role: .destructive, action: onDelete)
            }
            Button(S("通報してブロック", "Report & Block"), systemImage: "exclamationmark.bubble", role: .destructive, action: onReport)
        }
    }
}

/// 「Apple Musicで聴く」「Spotifyで聴く」。前に選んだアプリを上に出し、選んだアプリを覚えておく。Menu の中で使う
struct ListenMenuItems: View {
    let title: String
    let artist: String
    let appleMusicURL: String?
    @Environment(\.openURL) private var openURL
    @AppStorage(MusicApp.storageKey) private var preferred = MusicApp.appleMusic.rawValue

    private var apps: [MusicApp] {
        preferred == MusicApp.spotify.rawValue ? [.spotify, .appleMusic] : [.appleMusic, .spotify]
    }

    var body: some View {
        ForEach(apps) { app in
            switch app {
            case .appleMusic:
                if let link = appleMusicURL.flatMap(URL.init(string:)) {
                    Button(app.listenLabel, systemImage: "music.note") {
                        preferred = app.rawValue
                        openURL(link)
                    }
                }
            case .spotify:
                Button(app.listenLabel, systemImage: "headphones") {
                    preferred = app.rawValue
                    Task { openURL(await MusicLinks.spotifyURL(title: title, artist: artist, appleMusicURL: appleMusicURL)) }
                }
            }
        }
    }
}

/// 投稿へのコメント1件と、それにつながる返信（返信への返信も同じ流れにまとめ、古い順に並べる）
struct CommentThread: Identifiable {
    let root: PostComment
    let replies: [PostComment]
    /// コメントの ID → 名前（返信先の名前を出すため）
    let names: [String: String]
    var id: String { root.id }

    func name(of commentID: String?) -> String? {
        commentID.flatMap { names[$0] }
    }

    /// 返信先が消された・隠された返信は、投稿へのコメントとして出す
    static func threads(_ comments: [PostComment]) -> [CommentThread] {
        let byID = Dictionary(comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = byID.mapValues { $0.isMine ? S("あなた", "You", "나") : $0.nickname }
        func rootID(of comment: PostComment) -> String {
            var current = comment
            var seen: Set<String> = [comment.id]
            while let parent = current.replyTo.flatMap({ byID[$0] }), seen.insert(parent.id).inserted {
                current = parent
            }
            return current.id
        }
        var replies: [String: [PostComment]] = [:]
        var roots: [PostComment] = []
        for comment in comments.sorted(by: { $0.postedAt < $1.postedAt }) {
            let root = rootID(of: comment)
            if root == comment.id { roots.append(comment) } else { replies[root, default: []].append(comment) }
        }
        return roots.map { CommentThread(root: $0, replies: replies[$0.id] ?? [], names: names) }
    }
}
