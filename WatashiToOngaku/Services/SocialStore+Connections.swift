import CloudKit
import CryptoKit
import UIKit

// フレンドのフレンド・コメント・フレンドの投稿とコメントの通知。
// どれも SocialStore と同じく公開 DB に置き、レコード名を知っている人（＝鍵を知っているフレンド）だけが読める形にする。

/// フレンドのフレンド（申請できる人）
struct FriendSuggestion: Identifiable, Hashable {
    let code: String
    let nickname: String
    var avatarVersion = 0
    /// この人とフレンドになっている、自分のフレンドのニックネーム
    let via: [String]
    var id: String { code }
}

/// 投稿へのコメント
struct PostComment: Identifiable, Hashable {
    /// レコード名 "c-<投稿のレコード名>-<番号>"
    let id: String
    let code: String
    let nickname: String
    var avatarVersion = 0
    let text: String
    let postedAt: Date
    var isMine = false
    /// 返信先のコメント（レコード名）。nil なら投稿へのコメント
    var replyTo: String?
}

/// コメントへの絵文字のリアクション（1人1コメントに1つ。押し直すと変わる）
struct CommentReaction: Identifiable, Hashable {
    /// レコード名 "rx-<投稿のレコード名>-<番号>"
    let id: String
    let code: String
    let nickname: String
    let commentID: String
    let emoji: String
    var isMine = false
}

extension SocialStore {
    /// レコードを名前で読む。200件ずつに分けて、同時に読む（順に待つより速い）。どれか1つでも失敗したら nil
    func fetchRecords(_ ids: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]? = nil) async -> [CKRecord.ID: Result<CKRecord, Error>]? {
        guard !ids.isEmpty else { return [:] }
        let db = publicDB
        let chunks = ids.chunked(200)
        if chunks.count == 1 { return try? await db.records(for: chunks[0], desiredKeys: desiredKeys) }
        return try? await withThrowingTaskGroup(of: [CKRecord.ID: Result<CKRecord, Error>].self) { group in
            for chunk in chunks { group.addTask { try await db.records(for: chunk, desiredKeys: desiredKeys) } }
            var all: [CKRecord.ID: Result<CKRecord, Error>] = [:]
            for try await part in group { all.merge(part) { first, _ in first } }
            return all
        }
    }

    // MARK: - フレンドのフレンド
    //
    // 自分のフレンドのコードの一覧を "fl-<鍵>"（FriendList）に置く。鍵を知っているフレンドだけが読める。
    // フレンドは、その一覧から「フレンドのフレンド」を見つけて申請できる。
    // 「フレンドのフレンドに表示しない」にした人（FriendCode の hidden = 1）は、一覧に載せず、見る側でも外す。

    static func friendListID(secret: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "fl-\(secret)")
    }

    /// フレンドのフレンドに自分を出さない
    var hidesFromFriendsOfFriends: Bool {
        get { value("social_hideFromFoF") as? Bool ?? false }
        set {
            set(newValue, "social_hideFromFoF")
            objectWillChange.send()
        }
    }

    func setHidesFromFriendsOfFriends(_ hides: Bool) async {
        hidesFromFriendsOfFriends = hides
        guard state == .ready else { return }
        do { try await publishFriendCode() } catch { lastError = Self.describe(error) }
    }

    /// 自分のフレンドの一覧を置く（前に置いたものから変わったときだけ）
    func publishFriendList(excluding hidden: Set<String>) async {
        guard state == .ready, !isPreview else { return }
        let codes = links.map(\.code).filter { !hidden.contains($0) }.sorted()
        let stampKey = "social_friendList_\(secret)"
        guard local.stringArray(forKey: stampKey) != codes else { return }
        let record = CKRecord(recordType: "FriendList", recordID: Self.friendListID(secret: secret))
        record["codes"] = codes.isEmpty ? nil : codes as NSArray
        if (try? await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)) != nil {
            local.set(codes, forKey: stampKey)
        }
    }

    /// フレンドの一覧を読んで、共通のフレンドと、フレンドのフレンドを出す
    func loadSuggestions() async {
        guard state == .ready, !isPreview else { return }
        let links = self.links
        guard !links.isEmpty else {
            suggestions = []
            mutualFriends = [:]
            friendListsByCode = [:]
            fofProfiles = [:]
            return
        }
        var lists: [String: [String]] = [:]   // フレンドのコード → そのフレンドのフレンドのコード
        guard let found = await fetchRecords(links.map { Self.friendListID(secret: $0.secret) }) else { return }
        for link in links {
            // 一覧を置いたのが、そのフレンド本人か確かめる
            guard case .success(let record)? = found[Self.friendListID(secret: link.secret)],
                  record.creatorUserRecordID?.recordName == link.creator else { continue }
            lists[link.code] = record["codes"] as? [String] ?? []
        }
        let myCodes = Set(links.map(\.code))
        let names = Dictionary(friends.map { ($0.code, $0.nickname) }, uniquingKeysWith: { first, _ in first })
        var mutual: [String: [String]] = [:]
        var via: [String: [String]] = [:]     // フレンドのフレンドのコード → 間にいる自分のフレンドのコード
        let blocked = self.blocked
        for (friend, codes) in lists {
            for code in Set(codes) where code != friendCode && !blocked.contains(code) && code != friend {
                if myCodes.contains(code) {
                    if let name = names[code] { mutual[friend, default: []].append(name) }
                } else {
                    via[code, default: []].append(friend)
                }
            }
        }
        mutualFriends = mutual.mapValues { $0.sorted() }
        friendListsByCode = lists

        // 共通のフレンドが多い順。フレンドのプロフィールから一覧を開いたときにも使うので、全員分を読む
        let candidates = via.keys.sorted { (via[$0]!.count, $1) > (via[$1]!.count, $0) }.prefix(1000)
        var result: [FriendSuggestion] = []
        // アイコンの画像は、一覧に出たときに AvatarView が読む（1000人分を先に読まない）
        let profiles = await fetchRecords(candidates.map { CKRecord.ID(recordName: $0) },
                                          desiredKeys: ["nickname", "avatarVersion", "hidden"]) ?? [:]
        for code in candidates {
            guard case .success(let record)? = profiles[CKRecord.ID(recordName: code)],
                  (record["hidden"] as? Int ?? 0) == 0 else { continue }
            let version = record["avatarVersion"] as? Int ?? 0
            result.append(FriendSuggestion(code: code, nickname: record["nickname"] as? String ?? S("フレンド", "Friend"),
                                           avatarVersion: version,
                                           via: (via[code] ?? []).compactMap { names[$0] }.sorted()))
        }
        fofProfiles = Dictionary(result.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        suggestions = Array(result.prefix(100))
    }

    /// フレンドのプロフィールに出す、その人のフレンド
    enum FriendOfFriendEntry: Identifiable {
        case me
        case friend(Friend)
        case other(FriendSuggestion)
        var id: String {
            switch self {
            case .me: return "me"
            case .friend(let friend): return friend.code
            case .other(let person): return person.code
            }
        }
    }

    /// そのフレンドのフレンド一覧（共通のフレンドを先に）。一覧がまだ無ければ nil
    func friendsOf(_ friend: Friend) -> [FriendOfFriendEntry]? {
        guard let codes = friendListsByCode[friend.code] else { return nil }
        let mine = Dictionary(friends.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        var hasMe = false
        var mutual: [Friend] = [], others: [FriendSuggestion] = []
        for code in Set(codes) where code != friend.code && !blocked.contains(code) {
            if code == friendCode { hasMe = true }
            else if let known = mine[code] { mutual.append(known) }
            else if let person = fofProfiles[code] { others.append(person) }
        }
        return (hasMe ? [.me] : []) + mutual.sorted { $0.nickname < $1.nickname }.map { .friend($0) }
            + others.sorted { $0.nickname < $1.nickname }.map { .other($0) }
    }

    /// フレンドのフレンドへの申請の状態
    enum SuggestionStatus { case canRequest, requested, incoming }

    func status(of suggestion: FriendSuggestion) -> SuggestionStatus {
        if outgoingRequests.contains(where: { $0.code == suggestion.code }) { return .requested }
        if incomingRequests.contains(where: { $0.code == suggestion.code }) { return .incoming }
        return .canRequest
    }

    // MARK: - コメント
    //
    // コメントは "c-<投稿のレコード名>-<番号>"（Comment）に置く。投稿の鍵を知っている人（投稿した人とそのフレンド）だけが
    // 場所を知っていて、番号を 0 から順に読む（検索はしない）。番号の取り合いは claimSlot で先に置けた人のもの。
    // 投稿した人は "ch-<投稿のレコード名>"（CommentHide）に、自分の投稿から消したいコメントを並べられる。

    static let commentMaxLength = 300
    /// 一度に読む番号の数。読んだ範囲にコメントがあれば、続きも読む
    private static let commentPage = 10

    func canComment(on post: FriendPost) -> Bool {
        state == .ready
    }

    /// 投稿のレコード名（自分の投稿は FriendPost.id が "me-<日付>" なので、iCloud 上の名前に直す）
    func recordName(of post: FriendPost) -> String {
        post.friend.isMe ? postID(secret: secret, dayKey: post.dayKey).recordName : post.id
    }

    /// 投稿を置いた iCloud 利用者（コメントを隠す一覧が本人のものか確かめる）
    private func creator(of post: FriendPost) -> String? {
        post.friend.isMe ? CKCurrentUserDefaultName : links.first { $0.code == post.friend.code }?.creator
    }

    private static func commentHideID(_ postName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "ch-\(postName)")
    }

    /// 自分が書いたコメント（レコード名）。コードを作り直したときに書き換え、やめるときに消すために控える
    private var myComments: Set<String> {
        get { Set(value("social_comments") as? [String] ?? []) }
        set {
            // 1年より前の投稿へのコメントは控えから外す（Key-Value ストレージの容量を抑える）
            let oldest = DayKey.string(from: Calendar.current.date(byAdding: .day, value: -Self.plusTimelineDays, to: Date()) ?? Date())
            set(newValue.filter { (Self.dayKey(ofComment: $0) ?? oldest) >= oldest }.sorted(), "social_comments")
        }
    }

    /// "c-s-<鍵>-2026-11-23-3" → "2026-11-23"
    static func dayKey(ofComment name: String) -> String? {
        let parts = name.split(separator: "-")
        guard parts.count >= 5 else { return nil }
        return parts[(parts.count - 4)..<(parts.count - 1)].joined(separator: "-")
    }

    /// 投稿のコメントを読む（タイムラインのカードが画面に出たとき、まとめて）
    func fetchComments(for posts: [FriendPost]) async {
        guard state == .ready, !isPreview else { return }
        var pending = posts.filter(canComment(on:))
        guard !pending.isEmpty else { return }
        var records: [String: [CKRecord]] = [:]
        var hidden: [String: Set<String>] = [:]
        var start = 0
        while !pending.isEmpty, start < 1000 {
            var ids: [CKRecord.ID] = []
            for post in pending {
                let name = recordName(of: post)
                ids += (start..<start + Self.commentPage).map { CKRecord.ID(recordName: "c-\(name)-\($0)") }
                if start == 0 { ids.append(Self.commentHideID(name)) }
            }
            var found: [CKRecord.ID: CKRecord] = [:]
            guard let results = await fetchRecords(ids) else { return }
            for case let (id, .success(record)) in results { found[id] = record }
            pending = pending.filter { post in
                let name = recordName(of: post)
                if start == 0, let hide = found[Self.commentHideID(name)],
                   hide.creatorUserRecordID?.recordName == creator(of: post) {
                    hidden[post.id] = Set(hide["hidden"] as? [String] ?? [])
                }
                let page = (start..<start + Self.commentPage).compactMap { found[CKRecord.ID(recordName: "c-\(name)-\($0)")] }
                records[post.id, default: []] += page
                return !page.isEmpty
            }
            start += Self.commentPage
        }

        // コメントのコードが、そのコードの持ち主本人が置いたものか確かめる
        let blocked = self.blocked
        let codes = Set(records.values.joined().compactMap { $0["fromCode"] as? String }).subtracting(blocked)
        guard let owners = await fetchRecords(codes.map { CKRecord.ID(recordName: $0) },
                                              desiredKeys: ["nickname", "avatarVersion"]) else { return }
        var result = comments
        for post in posts where canComment(on: post) {
            let hide = hidden[post.id] ?? []
            result[post.id] = (records[post.id] ?? []).compactMap { record -> PostComment? in
                guard let code = record["fromCode"] as? String, codes.contains(code),
                      !hide.contains(record.recordID.recordName),
                      case .success(let owner)? = owners[CKRecord.ID(recordName: code)],
                      owner.creatorUserRecordID?.recordName == record.creatorUserRecordID?.recordName,
                      let text = record["text"] as? String, !text.isEmpty else { return nil }
                let version = owner["avatarVersion"] as? Int ?? 0
                AvatarStore.shared.fetchIfNeeded(code: code, version: version, in: publicDB)
                return PostComment(id: record.recordID.recordName, code: code,
                                   nickname: owner["nickname"] as? String ?? S("フレンド", "Friend"),
                                   avatarVersion: version, text: text,
                                   postedAt: record["postedAt"] as? Date ?? record.creationDate ?? Date(),
                                   isMine: code == friendCode, replyTo: record["replyTo"] as? String)
            }
            .sorted { $0.postedAt < $1.postedAt }
        }
        comments = result
    }

    /// コメントを書く。フレンドの投稿なら投稿した人に、返信なら返信先を書いた人（フレンドのとき）に通知する
    func postComment(_ raw: String, on post: FriendPost, replyTo parent: PostComment? = nil) async -> Bool {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.commentMaxLength))
        guard canComment(on: post), !text.isEmpty else { return false }
        let now = Date()
        if isPreview {
            comments[post.id, default: []].append(PostComment(id: UUID().uuidString, code: friendCode, nickname: nickname,
                                                              avatarVersion: avatarVersion, text: text, postedAt: now, isMine: true,
                                                              replyTo: parent?.id))
            return true
        }
        var fields: [String: CKRecordValue] = ["fromCode": friendCode as NSString, "text": text as NSString, "postedAt": now as NSDate]
        if let parent { fields["replyTo"] = parent.id as NSString }
        guard let name = await claimSlot(prefix: "c-\(recordName(of: post))-", type: "Comment", fields: fields) else {
            lastError = S("コメントを送れませんでした", "Couldn't post your comment", "댓글을 보내지 못했습니다")
            return false
        }
        myComments.insert(name)
        comments[post.id, default: []].append(PostComment(id: name, code: friendCode, nickname: nickname, avatarVersion: avatarVersion,
                                                          text: text, postedAt: now, isMine: true, replyTo: parent?.id))
        if !post.friend.isMe { await sendPing(kind: "comment", toSecret: post.friend.secret) }
        // 返信先を書いた人がフレンドなら知らせる（投稿した人本人なら、上のコメントの通知で足りる）
        if let parent, !parent.isMine, parent.code != post.friend.code,
           let link = links.first(where: { $0.code == parent.code }) {
            await sendPing(kind: "reply", toSecret: link.secret)
        }
        return true
    }

    /// 自分のコメントは消す。自分の投稿に付いたほかの人のコメントは、隠す一覧に加える
    func deleteComment(_ comment: PostComment, on post: FriendPost) async {
        guard state == .ready else { return }
        let previous = comments[post.id]
        comments[post.id]?.removeAll { $0.id == comment.id }
        guard !isPreview else { return }
        do {
            if comment.isMine {
                _ = try await publicDB.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: comment.id)])
                myComments.remove(comment.id)
            } else if post.friend.isMe {
                let id = Self.commentHideID(recordName(of: post))
                let record = (try? await publicDB.record(for: id)) ?? CKRecord(recordType: "CommentHide", recordID: id)
                let hidden = Set(record["hidden"] as? [String] ?? []).union([comment.id])
                record["hidden"] = hidden.sorted() as NSArray
                _ = try await save(record)
            }
        } catch {
            comments[post.id] = previous
            lastError = Self.describe(error)
        }
    }

    /// 不適切なコメントを開発者に知らせ、書いた人をブロックする（フレンドならフレンドもやめる）
    func report(_ comment: PostComment, on post: FriendPost, reason: String) async {
        let record = CKRecord(recordType: "Report")
        record["reportedCode"] = comment.code
        record["dayKey"] = post.dayKey
        record["title"] = S("コメント", "Comment", "댓글") + ": " + post.title
        record["memo"] = comment.text
        record["reason"] = reason
        record["reporterCode"] = friendCode
        _ = try? await save(record)
        for key in comments.keys { comments[key]?.removeAll { $0.code == comment.code } }
        if let friend = friends.first(where: { $0.code == comment.code }) {
            await remove(friend, block: true)
        } else {
            block(comment.code, nickname: comment.nickname)
            suggestions.removeAll { $0.code == comment.code }
        }
    }

    // MARK: - コメントへのリアクション
    //
    // リアクションは投稿ごとに "rx-<投稿のレコード名>-<番号>"（CommentReaction）に置く。
    // 中身はどのコメントへのものか（commentID）と絵文字。読むのはコメントと同じく番号を 0 から順に（検索はしない）。

    static let reactionEmojis = ["❤️", "😂", "😮", "😢", "🔥", "👏", "🎵"]

    /// 自分のリアクション：レコード名 → コメントの ID（コードを作り直したときに書き換え、やめるときに消す）
    private var myReactions: [String: String] {
        get { value("social_reactions") as? [String: String] ?? [:] }
        set {
            let oldest = DayKey.string(from: Calendar.current.date(byAdding: .day, value: -Self.plusTimelineDays, to: Date()) ?? Date())
            set(newValue.filter { (Self.dayKey(ofComment: $0.key) ?? oldest) >= oldest }, "social_reactions")
        }
    }

    /// 投稿のコメントに付いたリアクションを読む（コメントの画面を開いたとき）
    func fetchReactions(for post: FriendPost) async {
        guard canComment(on: post), !isPreview else { return }
        let name = recordName(of: post)
        var records: [CKRecord] = []
        var start = 0
        while start < 2000 {
            let ids = (start..<start + 50).map { CKRecord.ID(recordName: "rx-\(name)-\($0)") }
            guard let found = try? await publicDB.records(for: ids) else { return }
            let page = ids.compactMap { try? found[$0]?.get() }
            records += page
            if page.isEmpty { break }
            start += 50
        }
        // 置いたのがそのコードの持ち主本人か確かめる
        let codes = Set(records.compactMap { $0["fromCode"] as? String }).subtracting(blocked)
        var owners: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        for chunk in Array(codes).chunked(200) {
            guard let found = try? await publicDB.records(for: chunk.map { CKRecord.ID(recordName: $0) }, desiredKeys: ["nickname"]) else { return }
            owners.merge(found) { first, _ in first }
        }
        var result: [String: [CommentReaction]] = [:]
        for record in records {
            guard let code = record["fromCode"] as? String, codes.contains(code),
                  let commentID = record["commentID"] as? String,
                  let emoji = record["emoji"] as? String, Self.reactionEmojis.contains(emoji),
                  case .success(let owner)? = owners[CKRecord.ID(recordName: code)],
                  owner.creatorUserRecordID?.recordName == record.creatorUserRecordID?.recordName else { continue }
            // 同じ人の同じコメントへのリアクションは1つだけ
            guard !(result[commentID] ?? []).contains(where: { $0.code == code }) else { continue }
            result[commentID, default: []].append(CommentReaction(
                id: record.recordID.recordName, code: code, nickname: owner["nickname"] as? String ?? S("フレンド", "Friend"),
                commentID: commentID, emoji: emoji, isMine: code == friendCode))
        }
        for comment in comments[post.id] ?? [] { commentReactions[comment.id] = result[comment.id] ?? [] }
    }

    /// ほかの人のコメントにリアクションする。同じ絵文字をもう一度押すと取り消し、違う絵文字なら付け替える
    func react(_ emoji: String, to comment: PostComment, on post: FriendPost) async {
        guard canComment(on: post), !comment.isMine else { return }
        let previous = commentReactions[comment.id] ?? []
        let mine = previous.first(where: \.isMine)
        let removing = mine?.emoji == emoji
        var updated = previous.filter { !$0.isMine }
        if !removing {
            updated.append(CommentReaction(id: mine?.id ?? "pending", code: friendCode, nickname: nickname,
                                           commentID: comment.id, emoji: emoji, isMine: true))
        }
        commentReactions[comment.id] = updated
        guard !isPreview else { return }
        do {
            if let mine, removing {
                _ = try await publicDB.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: mine.id)])
                myReactions[mine.id] = nil
            } else if let mine, mine.id != "pending" {
                let record = CKRecord(recordType: "CommentReaction", recordID: CKRecord.ID(recordName: mine.id))
                record["emoji"] = emoji
                record["reactedAt"] = Date()
                _ = try await save(record)
            } else {
                let fields: [String: CKRecordValue] = ["fromCode": friendCode as NSString, "commentID": comment.id as NSString,
                                                       "emoji": emoji as NSString, "reactedAt": Date() as NSDate]
                guard let slot = await claimSlot(prefix: "rx-\(recordName(of: post))-", type: "CommentReaction", fields: fields) else {
                    throw CKError(.networkFailure)
                }
                myReactions[slot] = comment.id
                commentReactions[comment.id] = updated.map { $0.isMine
                    ? CommentReaction(id: slot, code: $0.code, nickname: $0.nickname, commentID: $0.commentID, emoji: $0.emoji, isMine: true)
                    : $0 }
            }
        } catch {
            commentReactions[comment.id] = previous
            lastError = Self.describe(error)
        }
    }

    /// コードを作り直したら、自分のコメントのコードも書き換える
    func moveCommentsToNewCode() async {
        for chunk in Array(myReactions.keys).chunked(200) {
            let records = chunk.map { name -> CKRecord in
                let record = CKRecord(recordType: "CommentReaction", recordID: CKRecord.ID(recordName: name))
                record["fromCode"] = friendCode
                return record
            }
            _ = try? await publicDB.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
        }
        for chunk in Array(myComments).chunked(200) {
            let records = chunk.map { name -> CKRecord in
                let record = CKRecord(recordType: "Comment", recordID: CKRecord.ID(recordName: name))
                record["fromCode"] = friendCode
                return record
            }
            _ = try? await publicDB.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
        }
    }

    // MARK: - 通知（フレンドの投稿・自分の投稿へのコメント）
    //
    // 公開 DB の Ping に「合図」を置き、フレンドは CKQuerySubscription でそれを購読する。
    // 合図には鍵から作った目印（tag）とニックネームだけを置き、曲やメモは置かない。目印から鍵は分からない。
    // - 投稿："p-<目印>"。その日はじめて今日の曲を共有したときに書き換える。フレンドは目印の一覧（IN）で購読する
    // - いいね・コメント："k-（いいね）/ q-（コメント）<書いた人のコード>-<相手の目印の頭>"。投稿した人は自分の目印（==）で購読する
    // 検索に使うのは Ping の tag だけ（QUERYABLE の索引が要る）。

    /// 鍵から作る目印（HMAC）。種類ごとに別の値にする
    static func pingTag(secret: String, kind: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("OurMusic-ping-\(kind)".utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return mac.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func postPingID(secret: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "p-\(pingTag(secret: secret, kind: "post"))")
    }

    /// フレンドが今日の曲を共有したら通知する
    var notifiesFriendPosts: Bool {
        get { local.object(forKey: "notify_friendPosts") as? Bool ?? true }
        set {
            local.set(newValue, forKey: "notify_friendPosts")
            objectWillChange.send()
            Task { await updateSubscriptions() }
        }
    }

    /// 自分の投稿にコメントが付いたら通知する
    var notifiesComments: Bool {
        get { local.object(forKey: "notify_comments") as? Bool ?? true }
        set {
            local.set(newValue, forKey: "notify_comments")
            objectWillChange.send()
            Task { await updateSubscriptions() }
        }
    }

    /// 自分の投稿にいいねが付いたら通知する
    var notifiesLikes: Bool {
        get { local.object(forKey: "notify_likes") as? Bool ?? true }
        set {
            local.set(newValue, forKey: "notify_likes")
            objectWillChange.send()
            Task { await updateSubscriptions() }
        }
    }

    /// 自分が置いたいいね・コメントの合図（やめるときに消す）
    private var commentPings: Set<String> {
        get { Set(value("social_commentPings") as? [String] ?? []) }
        set { set(newValue.sorted(), "social_commentPings") }
    }

    /// 今日の曲を共有したら（その日1回だけ）フレンドに合図を送る
    func pingTodayIfNeeded() async {
        let today = DayKey.string(from: Date())
        guard state == .ready, !isPreview, local.string(forKey: "social_pingedDay") != today,
              let entry = localEntries.first(where: { $0.dayKey == today }), entry.shareSong,
              uploadedStamps[today] == Self.stamp(entry) else { return }
        let id = Self.postPingID(secret: secret)
        let record = CKRecord(recordType: "Ping", recordID: id)
        record["tag"] = String(id.recordName.dropFirst(2))
        // 合図は誰でも tag で検索できるので、名前は自分の鍵で閉じた暗号文だけを置く（フレンドの端末の通知拡張が開く）
        record["nickname"] = PingCrypto.seal(nickname, secret: secret)
        record["dayKey"] = today
        if (try? await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)) != nil {
            local.set(today, forKey: "social_pingedDay")
        }
    }

    /// フレンドの投稿にいいね・コメントしたら、投稿した人に合図を送る（相手ごと・種類ごとに1件を書き換える）
    func sendPing(kind: String, toSecret ownerSecret: String) async {
        guard !isPreview else { return }
        let tag = Self.pingTag(secret: ownerSecret, kind: kind)
        let prefix = ["like": "k", "reply": "y"][kind] ?? "q"
        // レコード名は自分の鍵から作る推測できない目印（フレンドコードを入れると、Ping の一覧から誰が反応したかが分かってしまう）
        let id = CKRecord.ID(recordName: "\(prefix)-\(Self.pingTag(secret: secret, kind: "from-\(kind)-\(tag)"))")
        let record = CKRecord(recordType: "Ping", recordID: id)
        record["tag"] = tag
        // 名前は相手の鍵で閉じる（相手の端末の通知拡張だけが開ける）
        record["nickname"] = PingCrypto.seal(nickname, secret: ownerSecret)
        record["dayKey"] = DayKey.string(from: Date())
        if (try? await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)) != nil {
            commentPings.insert(id.recordName)
        }
    }

    private static let subscriptionPrefix = "om-"

    /// 購読をいまのフレンド・設定・言語に合わせる（変わったときだけ作り直す）
    func updateSubscriptions() async {
        guard state == .ready, !isPreview else { return }
        let blocked = self.blocked
        let postTags = notifiesFriendPosts
            ? links.filter { !blocked.contains($0.code) }.map { Self.pingTag(secret: $0.secret, kind: "post") }.sorted() : []
        let commentTag = notifiesComments ? Self.pingTag(secret: secret, kind: "comment") : nil
        let likeTag = notifiesLikes ? Self.pingTag(secret: secret, kind: "like") : nil
        let language = ThemeStore.shared.language
        let signature = (postTags + [commentTag ?? "-", likeTag ?? "-", language, "v4"]).joined(separator: ",")
        guard local.string(forKey: "social_subscriptionSignature") != signature else { return }

        var saving: [CKSubscription] = []
        // IN に並べる数を抑えるため、50人ずつに分ける
        // 通知拡張に渡す「tag → 名前を開く鍵と文の型」
        var routes: [String: PingCrypto.Route] = [:]
        let postFormat = S("%@さんが今日の一曲を選びました", "%@ picked today's song", "%@님이 오늘의 한 곡을 골랐습니다")
        for link in links where !blocked.contains(link.code) && notifiesFriendPosts {
            routes[Self.pingTag(secret: link.secret, kind: "post")] = PingCrypto.makeRoute(secret: link.secret, format: postFormat)
        }
        for (index, tags) in postTags.chunked(50).enumerated() {
            let subscription = CKQuerySubscription(recordType: "Ping", predicate: NSPredicate(format: "tag IN %@", tags),
                                                   subscriptionID: "\(Self.subscriptionPrefix)posts-\(index)",
                                                   options: [.firesOnRecordCreation, .firesOnRecordUpdate])
            subscription.notificationInfo = Self.notificationInfo(
                S("フレンドが今日の一曲を選びました", "A friend picked today's song", "친구가 오늘의 한 곡을 골랐습니다"))
            saving.append(subscription)
        }
        if let commentTag {
            let subscription = CKQuerySubscription(recordType: "Ping", predicate: NSPredicate(format: "tag == %@", commentTag),
                                                   subscriptionID: "\(Self.subscriptionPrefix)comments",
                                                   options: [.firesOnRecordCreation, .firesOnRecordUpdate])
            subscription.notificationInfo = Self.notificationInfo(
                S("フレンドがあなたの曲にコメントしました", "A friend commented on your song", "친구가 내 곡에 댓글을 남겼습니다"))
            saving.append(subscription)
            // 自分のコメントへの返信も、コメントの通知に含める
            let replies = CKQuerySubscription(recordType: "Ping",
                                              predicate: NSPredicate(format: "tag == %@", Self.pingTag(secret: secret, kind: "reply")),
                                              subscriptionID: "\(Self.subscriptionPrefix)replies",
                                              options: [.firesOnRecordCreation, .firesOnRecordUpdate])
            replies.notificationInfo = Self.notificationInfo(
                S("フレンドがあなたのコメントに返信しました", "A friend replied to your comment", "친구가 내 댓글에 답글을 남겼습니다"))
            saving.append(replies)
        }
        if let likeTag {
            let subscription = CKQuerySubscription(recordType: "Ping", predicate: NSPredicate(format: "tag == %@", likeTag),
                                                   subscriptionID: "\(Self.subscriptionPrefix)likes",
                                                   options: [.firesOnRecordCreation, .firesOnRecordUpdate])
            subscription.notificationInfo = Self.notificationInfo(
                S("フレンドがあなたの曲にいいねしました", "A friend liked your song", "친구가 내 곡에 좋아요를 눌렀습니다"))
            saving.append(subscription)
        }
        if let commentTag {
            routes[commentTag] = PingCrypto.makeRoute(secret: secret, format: S("%@さんがあなたの曲にコメントしました", "%@ commented on your song", "%@님이 내 곡에 댓글을 남겼습니다"))
            routes[Self.pingTag(secret: secret, kind: "reply")] = PingCrypto.makeRoute(
                secret: secret, format: S("%@さんがあなたのコメントに返信しました", "%@ replied to your comment", "%@님이 내 댓글에 답글을 남겼습니다"))
        }
        if let likeTag {
            routes[likeTag] = PingCrypto.makeRoute(secret: secret, format: S("%@さんがあなたの曲にいいねしました", "%@ liked your song", "%@님이 내 곡에 좋아요를 눌렀습니다"))
        }
        PingCrypto.saveRoutes(routes)
        do {
            let existing = try await publicDB.allSubscriptions().map(\.subscriptionID)
                .filter { $0.hasPrefix(Self.subscriptionPrefix) }
            let keep = Set(saving.map(\.subscriptionID))
            let deleting = existing.filter { !keep.contains($0) }
            if !saving.isEmpty || !deleting.isEmpty {
                let (saved, _) = try await publicDB.modifySubscriptions(saving: saving, deleting: deleting)
                for result in saved.values { _ = try result.get() }
            }
            local.set(signature, forKey: "social_subscriptionSignature")
            if !saving.isEmpty { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            print("[Social] subscriptions failed: \(Self.describe(error))")
        }
    }

    /// 通知の文。サーバーが作るのは誰からかを書かない汎用の文で、端末の通知拡張（NotificationService）が
    /// 合図の暗号化された名前を開けたら「〇〇さんが…」に書き換える。そのため tag と nickname を通知に載せる
    private static func notificationInfo(_ text: String) -> CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()
        info.alertBody = text
        info.desiredKeys = ["tag", "nickname"]
        info.shouldSendMutableContent = true
        info.soundName = "default"
        return info
    }

    // MARK: - スクリーンショット用のサンプル

    /// -uiPreview のとき：コメント・共通のフレンド・フレンドのフレンドの見本
    func loadPreviewConnections() {
        let now = Date()
        mutualFriends = ["MIO23456": ["Ken", "Yui"], "KEN23456": ["Mio"], "YUI23456": ["Mio"]]
        suggestions = [
            FriendSuggestion(code: "HARU2345", nickname: "Haru", via: ["Ken", "Mio", "Yui"]),
            FriendSuggestion(code: "RIN23456", nickname: "Rin", via: ["Mio", "Yui"]),
            FriendSuggestion(code: "TAKU2345", nickname: "Taku", via: ["Ken"]),
        ]
        if let first = timeline.first {
            commentReactions = [
                "\(first.id)-0": [
                    CommentReaction(id: "rx-a", code: "YUI23456", nickname: "Yui", commentID: "\(first.id)-0", emoji: "❤️"),
                    CommentReaction(id: "rx-b", code: "KEN23456", nickname: "Ken", commentID: "\(first.id)-0", emoji: "❤️"),
                    CommentReaction(id: "rx-c", code: friendCode, nickname: nickname, commentID: "\(first.id)-0", emoji: "😂", isMine: true),
                ],
                "\(first.id)-1": [CommentReaction(id: "rx-d", code: "MIO23456", nickname: "Mio", commentID: "\(first.id)-1", emoji: "🔥")],
            ]
        }
        fofProfiles = Dictionary(suggestions.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        friendListsByCode = [
            "MIO23456": [friendCode, "KEN23456", "YUI23456", "HARU2345", "RIN23456"],
            "KEN23456": [friendCode, "MIO23456", "HARU2345", "TAKU2345"],
            "YUI23456": [friendCode, "MIO23456", "HARU2345", "RIN23456"],
        ]
        let samples: [(String, String, String, Double)] = [
            ("Mio", "MIO23456", S("この曲わたしも大好き！", "I love this song too!", "이 곡 나도 정말 좋아해!"), -5400),
            ("Yui", "YUI23456", S("イントロから最高だよね", "The intro is the best", "인트로부터 최고지"), -3000),
            ("Sora", friendCode, S("でしょ！朝に聴くとちょうどいい", "Right? Perfect for mornings", "그치! 아침에 듣기 딱 좋아"), -1200),
        ]
        for (index, post) in timeline.prefix(3).enumerated() {
            let count = [3, 1, 2][index]
            comments[post.id] = samples.prefix(count).enumerated().map { offset, sample in
                PostComment(id: "\(post.id)-\(offset)", code: sample.1, nickname: sample.0, text: sample.2,
                            postedAt: now.addingTimeInterval(sample.3), isMine: sample.1 == friendCode,
                            // Yui は Mio に、Sora（あなた）は Yui に返信している
                            replyTo: offset == 0 ? nil : "\(post.id)-\(offset - 1)")
            }
        }
    }

    // MARK: - やめるとき

    /// フレンドの一覧・合図・コメント・購読を消す（フレンド機能をやめるとき）
    func deleteSocialExtras() async {
        let ids = [Self.friendListID(secret: secret), Self.postPingID(secret: secret)]
            + myComments.map { CKRecord.ID(recordName: $0) } + commentPings.map { CKRecord.ID(recordName: $0) }
            + myReactions.keys.map { CKRecord.ID(recordName: $0) }
        for chunk in ids.chunked(200) {
            _ = try? await publicDB.modifyRecords(saving: [], deleting: chunk)
        }
        if let existing = try? await publicDB.allSubscriptions().map(\.subscriptionID).filter({ $0.hasPrefix(Self.subscriptionPrefix) }),
           !existing.isEmpty {
            _ = try? await publicDB.modifySubscriptions(saving: [], deleting: existing)
        }
        local.removeObject(forKey: "social_friendList_\(secret)")
    }
}
