import CloudKit
import Combine
import SwiftData
import UIKit

/// フレンドとの音楽の共有（CloudKit の公開データベース）。
///
/// 利用者の iCloud ストレージを使わないよう、すべて公開 DB に置く（iCloud が満杯の人でも使える）。
/// 公開 DB は誰でも読めるので、「鍵」を知っている人だけが読める形にする：
/// - 利用者ごとにランダムな鍵（secret）を作り、投稿のレコード名を "s-<鍵>-<日付>" にする。
///   Post に検索用の索引は付けないので、鍵を知らない人は投稿を探し出せない。
/// - フレンドコード（8文字）のレコード "FriendCode"（レコード名 = コード）に鍵とニックネームを置く。
///   コード・招待リンク・QR コードを受け取る ＝ 鍵を受け取る、ということになる。
/// - 相手を追加したら、相手の「郵便受け」（レコード名 "r-<相手のコード>-<番号>" の 64 枠）に自分のコードを置き、
///   相手も自動で追加する（相互フレンド）。郵便受けもレコード名を指定して読むだけで、検索はしない。
/// - どのレコードにも検索用の索引を付けない（付けると他人のコードや投稿を探し出せてしまう）。
/// - フレンドをやめる・ブロックしたら、自分の鍵とコードを作り直し、残りのフレンドにだけ新しいコードを届ける。
@MainActor
final class SocialStore: ObservableObject {
    static let shared = SocialStore()

    static let containerID = "iCloud.com.taigayanai.watashitoongaku"
    static let inviteBaseURL = "https://taigayanai-git.github.io/WatashiToOngaku/add.html"
    /// タイムラインに出す期間（日）
    private static let timelineDays = 30

    enum State: Equatable {
        case notSetUp          // ニックネーム未設定（フレンド機能を使っていない）
        case unavailable(String)
        case ready
    }

    @Published private(set) var state: State = .notSetUp
    @Published private(set) var nickname = ""
    @Published private(set) var friendCode = ""
    @Published private(set) var avatarVersion = 0
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var timeline: [FriendPost] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    var inviteURL: URL? {
        friendCode.isEmpty ? nil : URL(string: "\(Self.inviteBaseURL)?c=\(friendCode)")
    }

    private var publicDB: CKDatabase { CKContainer(identifier: Self.containerID).publicCloudDatabase }

    // MARK: - 端末に残す情報（iCloud の Key-Value にも控えて、入れ直しても引き継ぐ）

    private let local = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default

    private func value(_ key: String) -> Any? { local.object(forKey: key) ?? cloud.object(forKey: key) }
    private func set(_ value: Any?, _ key: String) {
        local.set(value, forKey: key)
        cloud.set(value, forKey: key)
        cloud.synchronize()
    }

    private var secret: String {
        get { value("social_secret") as? String ?? "" }
        set { set(newValue, "social_secret") }
    }
    private var friendCodes: [String] {
        get { value("social_friends") as? [String] ?? [] }
        set { set(newValue, "social_friends") }
    }
    private var blocked: Set<String> {
        get { Set(value("social_blocked") as? [String] ?? []) }
        set { set(Array(newValue), "social_blocked") }
    }
    /// 自分のアイコン（128px の JPEG）。端末にも置いておき、コードを作り直したときにも付け直す
    private var myAvatarFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("my-avatar.jpg")
    }

    private var handledRequests: Set<String> {
        get { Set(local.stringArray(forKey: "social_handledRequests") ?? []) }
        set { local.set(Array(newValue), forKey: "social_handledRequests") }
    }

    // MARK: - はじめる

    /// 起動時：以前フレンド機能を使っていたら、読み込んで更新する
    func start() async {
        cloud.synchronize()
        guard let savedName = value("social_nickname") as? String, !savedName.isEmpty else {
            state = .notSetUp
            return
        }
        await setUp(nickname: savedName)
    }

    /// ニックネームを決めてフレンド機能を使い始める
    func setUp(nickname newName: String) async {
        var step = "account"
        do {
            guard try await CKContainer(identifier: Self.containerID).accountStatus() == .available else {
                state = .unavailable(S("iCloud にサインインすると、フレンド機能を使えます。「設定」アプリで iCloud にサインインしてください。",
                                       "Sign in to iCloud in the Settings app to use friends."))
                return
            }
            if secret.isEmpty { secret = Self.random(24) }
            if (value("social_code") as? String ?? "").isEmpty { set(Self.random(8), "social_code") }
            friendCode = value("social_code") as? String ?? ""
            avatarVersion = value("social_avatarVersion") as? Int ?? 0
            nickname = newName
            set(newName, "social_nickname")

            step = "friendCode"
            try await publishFriendCode()

            state = .ready
            step = "upload"
            await uploadAll()
            await refresh()
        } catch {
            print("[Social] setUp failed at \(step): \(Self.describe(error))")
            state = .unavailable(S("iCloud に接続できませんでした。", "Couldn't connect to iCloud.")
                                 + "\n(\(step)) " + Self.describe(error))
        }
    }

    /// コード → 鍵・ニックネーム の対応表を置く
    private func publishFriendCode() async throws {
        let id = CKRecord.ID(recordName: friendCode)
        let record = (try? await publicDB.record(for: id)) ?? CKRecord(recordType: "FriendCode", recordID: id)
        record["secret"] = secret
        record["nickname"] = nickname
        // アイコンは版が変わったときだけ付け直す（毎回アップロードしない）
        if avatarVersion > 0, (record["avatarVersion"] as? Int) != avatarVersion,
           FileManager.default.fileExists(atPath: myAvatarFile.path) {
            record["avatar"] = CKAsset(fileURL: myAvatarFile)
            record["avatarVersion"] = avatarVersion
        }
        _ = try await save(record)
    }

    /// アイコンを変える（写真を 128px に縮めて置く）
    func setAvatar(_ photo: Data) async -> Bool {
        guard state == .ready, let data = AvatarStore.thumbnail(from: photo) else { return false }
        do {
            try FileManager.default.createDirectory(at: myAvatarFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: myAvatarFile)
            let version = Int(Date().timeIntervalSince1970)
            avatarVersion = version
            set(version, "social_avatarVersion")
            AvatarStore.shared.storeOwn(data, code: friendCode, version: version)
            try await publishFriendCode()
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    /// 新しいニックネームにする
    func rename(_ newName: String) async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard state == .ready, !name.isEmpty else { return }
        nickname = name
        set(name, "social_nickname")
        do { try await publishFriendCode() } catch { lastError = Self.describe(error) }
        await refresh()
    }

    /// 紛らわしい文字（0/O, 1/I）を除いたランダムな文字列
    private static func random(_ length: Int) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    // MARK: - 投稿

    private func postID(secret: String, dayKey: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "s-\(secret)-\(dayKey)")
    }

    func upload(_ entry: SongEntry) async {
        guard state == .ready else { return }
        let id = postID(secret: secret, dayKey: entry.dayKey)
        guard entry.shareSong else {
            _ = try? await publicDB.modifyRecords(saving: [], deleting: [id])
            uploadedStamps[entry.dayKey] = Self.stamp(entry)
            return
        }
        do {
            _ = try await save(postRecord(entry, id: id))
            uploadedStamps[entry.dayKey] = Self.stamp(entry)
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// 投稿のレコードを作る（自分だけが書くので、サーバーの内容を読まずに丸ごと上書きする）
    private func postRecord(_ entry: SongEntry, id: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: "Post", recordID: id)
        record["dayKey"] = entry.dayKey
        record["songID"] = entry.songID
        record["title"] = entry.title
        record["artist"] = entry.artist
        record["albumTitle"] = entry.albumTitle
        record["artworkURL"] = entry.artworkURL
        record["previewURL"] = entry.previewURL
        record["appleMusicURL"] = entry.appleMusicURL
        record["memo"] = entry.shareMemo ? entry.memo : ""
        record["postedAt"] = entry.createdAt
        return record
    }

    func deletePost(dayKey: String) async {
        guard state == .ready else { return }
        _ = try? await publicDB.modifyRecords(saving: [], deleting: [postID(secret: secret, dayKey: dayKey)])
        uploadedStamps[dayKey] = nil
    }

    private var localEntries: [SongEntry] {
        (try? AppContainer.shared.mainContext.fetch(FetchDescriptor<SongEntry>())) ?? []
    }

    /// 日付 → 置いた内容の印。変わった記録だけを置き直すために使う（鍵を作り直したら空にする）
    private var uploadedStamps: [String: String] {
        get { local.dictionary(forKey: "social_uploaded_\(secret)") as? [String: String] ?? [:] }
        set { local.set(newValue, forKey: "social_uploaded_\(secret)") }
    }

    private static func stamp(_ entry: SongEntry) -> String {
        [entry.songID, entry.memo, "\(entry.shareSong)", "\(entry.shareMemo)", "\(entry.createdAt.timeIntervalSince1970)"].joined(separator: "|")
    }

    /// すべての記録を置く（月・年のプレイリストでフレンドが過去の曲も聴けるように）。
    /// 前回から変わった記録だけを、200件ずつまとめて保存する
    private func uploadAll() async {
        var stamps = uploadedStamps
        let changed = localEntries.filter { stamps[$0.dayKey] != Self.stamp($0) }
        for chunk in changed.chunked(200) {
            let saving = chunk.filter(\.shareSong).map { postRecord($0, id: postID(secret: secret, dayKey: $0.dayKey)) }
            let deleting = chunk.filter { !$0.shareSong }.map { postID(secret: secret, dayKey: $0.dayKey) }
            do {
                let (saved, deleted) = try await publicDB.modifyRecords(saving: saving, deleting: deleting, savePolicy: .allKeys)
                for entry in chunk {
                    let id = postID(secret: secret, dayKey: entry.dayKey)
                    let ok = entry.shareSong ? (try? saved[id]?.get()) != nil : deleted[id] != nil
                    if ok { stamps[entry.dayKey] = Self.stamp(entry) }
                }
            } catch {
                print("[Social] uploadAll failed: \(Self.describe(error))")
                break
            }
        }
        uploadedStamps = stamps
    }

    // MARK: - フレンドの追加

    /// フレンドコードで追加する。相手にも自分を追加してもらう申請を置く
    func addFriend(code raw: String) async -> Bool {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard state == .ready else { lastError = S("先にニックネームを決めてください", "Set your nickname first"); return false }
        guard code.count == 8 else { lastError = S("フレンドコードは8文字です", "Friend codes are 8 characters"); return false }
        guard code != friendCode else { lastError = S("自分のコードです", "That's your own code"); return false }
        guard !blocked.contains(code) else { lastError = S("ブロック中のユーザーです", "You've blocked this user"); return false }
        guard (try? await publicDB.record(for: CKRecord.ID(recordName: code))) != nil else {
            lastError = S("このコードのユーザーが見つかりません", "No user found for this code")
            return false
        }
        if !friendCodes.contains(code) { friendCodes.append(code) }
        await sendFriendRequest(to: code)
        await refresh()
        return true
    }

    /// 招待リンク・QR コード（…/add.html?c=コード または watashitoongaku://add?c=コード）から追加する
    func addFriend(url: URL) async -> Bool {
        guard let code = Self.code(in: url) else {
            lastError = S("私と音楽の招待リンクではありません", "This isn't a Me & Music invite link")
            return false
        }
        return await addFriend(code: code)
    }

    static func code(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "c" }?.value
    }

    /// 郵便受けの枠の数。送る側はコードから決まる枠から順に空きを探す
    private static let inboxSlots = 64

    private static func inboxID(_ code: String, _ slot: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "r-\(code)-\(slot)")
    }

    private func sendFriendRequest(to code: String, previousCode: String? = nil) async {
        let start = abs(friendCode.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.inboxSlots
        for offset in 0..<Self.inboxSlots {
            let id = Self.inboxID(code, (start + offset) % Self.inboxSlots)
            // 自分が前に置いた枠なら上書きする。他人の枠なら次へ
            if let existing = try? await publicDB.record(for: id) {
                guard existing.creatorUserRecordID?.recordName == CKCurrentUserDefaultName else { continue }
                existing["fromCode"] = friendCode
                existing["previousCode"] = previousCode
                existing["sentAt"] = Date()
                if (try? await save(existing)) != nil { return }
                continue
            }
            let request = CKRecord(recordType: "FriendRequest", recordID: id)
            request["fromCode"] = friendCode
            request["previousCode"] = previousCode
            request["sentAt"] = Date()
            if (try? await save(request)) != nil { return }
        }
    }

    /// 自分の郵便受けを見て、相手を追加する（相互フレンドにする）。
    /// 相手がコードを作り直したときは previousCode で古いコードを置き換える
    private func processFriendRequests() async {
        let ids = (0..<Self.inboxSlots).map { Self.inboxID(friendCode, $0) }
        guard let found = try? await publicDB.records(for: ids) else { return }
        var codes = friendCodes
        var handled = handledRequests
        for case let (_, .success(record)) in found {
            let from = record["fromCode"] as? String ?? ""
            let stamp = "\(record.recordID.recordName)@\(record.modificationDate?.timeIntervalSince1970 ?? 0)"
            guard !from.isEmpty, !handled.contains(stamp) else { continue }
            handled.insert(stamp)
            guard !blocked.contains(from) else { continue }
            if let previous = record["previousCode"] as? String {
                guard codes.contains(previous) else { continue } // やめたフレンドのコード更新は受け取らない
                codes.removeAll { $0 == previous }
            }
            if !codes.contains(from) { codes.append(from) }
        }
        handledRequests = handled
        friendCodes = codes
    }

    // MARK: - タイムライン

    func refresh() async {
        guard state == .ready, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await processFriendRequests()

        // フレンドのコード → 鍵・ニックネーム
        let codeIDs = friendCodes.map { CKRecord.ID(recordName: $0) }
        // アイコン画像は取らず、版番号だけ取る（画像は AvatarStore が必要なときだけ取る）
        let codeRecords = (try? await publicDB.records(for: codeIDs, desiredKeys: ["secret", "nickname", "avatarVersion"])) ?? [:]
        var newFriends: [Friend] = []
        for code in friendCodes {
            guard case .success(let record)? = codeRecords[CKRecord.ID(recordName: code)],
                  let secret = record["secret"] as? String else { continue }
            let version = record["avatarVersion"] as? Int ?? 0
            newFriends.append(Friend(code: code, nickname: record["nickname"] as? String ?? S("フレンド", "Friend"),
                                     secret: secret, avatarVersion: version))
            AvatarStore.shared.fetchIfNeeded(code: code, version: version, in: publicDB)
        }

        friends = newFriends.sorted { $0.nickname < $1.nickname }
        postCache = [:]

        // 各フレンドの最近の投稿を、レコード名を指定して取り出す（検索はしない）
        let today = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(Self.timelineDays - 1), to: today)!
        let days = Set(Self.dayKeys(from: start, to: today))
        let posts = await posts(from: start, to: today, includeAllOfMine: false)
        timeline = posts.filter { days.contains($0.dayKey) }.sorted { $0.postedAt > $1.postedAt }
    }

    // MARK: - 期間の投稿（みんなのプレイリスト）

    /// レコード名 → 投稿（無ければ nil）。タイムラインを更新するたびに空にする
    private var postCache: [String: FriendPost?] = [:]

    private var me: Friend {
        Friend(code: friendCode, nickname: nickname, secret: secret, avatarVersion: avatarVersion, isMe: true)
    }

    /// 期間内の、フレンドと自分の投稿。
    /// includeAllOfMine なら自分の記録は共有していない日の曲も入れる（自分だけが見るプレイリスト用）
    func posts(from start: Date, to end: Date, includeAllOfMine: Bool = true) async -> [FriendPost] {
        let days = Self.dayKeys(from: start, to: min(end, Date()))
        var result: [FriendPost] = []
        if state == .ready {
            for friend in friends {
                let ids = days.map { postID(secret: friend.secret, dayKey: $0) }
                let missing = ids.filter { postCache[$0.recordName] == nil }
                for chunk in missing.chunked(200) {
                    guard let found = try? await publicDB.records(for: chunk) else { continue }
                    for id in chunk {
                        postCache[id.recordName] = (try? found[id]?.get()).map { FriendPost(record: $0, friend: friend) }
                    }
                }
                result += ids.compactMap { postCache[$0.recordName] ?? nil }
            }
        }
        let keys = Set(days)
        let mine = localEntries.filter { keys.contains($0.dayKey) && (includeAllOfMine || $0.shareSong) }
        result += mine.map { FriendPost(entry: $0, me: me) }
        return result
    }

    static func dayKeys(from start: Date, to end: Date) -> [String] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: start)
        var keys: [String] = []
        while day <= end {
            keys.append(DayKey.string(from: day))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return keys
    }

    // MARK: - フレンド解除・ブロック・通報

    /// フレンドをやめる。自分の鍵とコードを作り直して、相手が読めないようにする
    func remove(_ friend: Friend, block: Bool) async {
        if block { blocked.insert(friend.code) }
        friendCodes.removeAll { $0 == friend.code }
        friends.removeAll { $0.code == friend.code }
        timeline.removeAll { $0.friend.code == friend.code }
        await rotateIdentity()
    }

    private func rotateIdentity() async {
        let oldSecret = secret, oldCode = friendCode
        secret = Self.random(24)
        friendCode = Self.random(8)
        set(friendCode, "social_code")
        // 新しいコードのレコードにもアイコンを付け直す
        if avatarVersion > 0, let data = try? Data(contentsOf: myAvatarFile) {
            AvatarStore.shared.storeOwn(data, code: friendCode, version: avatarVersion)
        }
        do { try await publishFriendCode() } catch { lastError = Self.describe(error) }
        await uploadAll()
        // 古い投稿と古いコードを消す
        let oldIDs = localEntries.map { postID(secret: oldSecret, dayKey: $0.dayKey) } + [CKRecord.ID(recordName: oldCode)]
        for chunk in oldIDs.chunked(200) {
            _ = try? await publicDB.modifyRecords(saving: [], deleting: chunk)
        }
        local.removeObject(forKey: "social_uploaded_\(oldSecret)")
        // 残っているフレンドに新しいコードを届ける
        for code in friendCodes { await sendFriendRequest(to: code, previousCode: oldCode) }
        await refresh()
    }

    /// 不適切な投稿を開発者に知らせる（公開 DB の Report に残す）。送ったあと相手はブロックする
    func report(_ post: FriendPost, reason: String) async {
        let record = CKRecord(recordType: "Report")
        record["reportedCode"] = post.friend.code
        record["dayKey"] = post.dayKey
        record["title"] = post.title
        record["memo"] = post.memo
        record["reason"] = reason
        record["reporterCode"] = friendCode
        _ = try? await save(record)
        await remove(post.friend, block: true)
    }

    // MARK: - CloudKit の小さな手助け

    private func save(_ record: CKRecord) async throws -> CKRecord {
        let (results, _) = try await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        guard let result = results[record.recordID] else { return record }
        return try result.get()
    }

    /// CKError の中身（まとめて保存したときの個別のエラーも）を読める形にする
    static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        var text = "CKError \(ck.code.rawValue): \(ck.localizedDescription)"
        for (id, sub) in ck.partialErrorsByItemID ?? [:] {
            let name = (id as? CKRecord.ID)?.recordName ?? "\(id)"
            text += "\n- \(name): \(sub.localizedDescription)"
        }
        return text
    }
}

struct Friend: Identifiable, Hashable {
    let code: String
    let nickname: String
    let secret: String
    var avatarVersion = 0
    var isMe = false
    var id: String { code }
}

struct FriendPost: Identifiable {
    let id: String
    let friend: Friend
    let dayKey: String
    let songID: String
    let title: String
    let artist: String
    let artworkURL: String
    let previewURL: String?
    let appleMusicURL: String?
    let memo: String
    let postedAt: Date

    init(record: CKRecord, friend: Friend) {
        id = record.recordID.recordName
        self.friend = friend
        dayKey = record["dayKey"] as? String ?? ""
        songID = record["songID"] as? String ?? id
        title = record["title"] as? String ?? ""
        artist = record["artist"] as? String ?? ""
        artworkURL = record["artworkURL"] as? String ?? ""
        previewURL = record["previewURL"] as? String
        appleMusicURL = record["appleMusicURL"] as? String
        memo = record["memo"] as? String ?? ""
        postedAt = record["postedAt"] as? Date ?? record.modificationDate ?? Date()
    }

    /// 自分の投稿（端末内の記録から、フレンドに見えている内容で作る）
    init(entry: SongEntry, me: Friend) {
        id = "me-" + entry.dayKey
        friend = me
        dayKey = entry.dayKey
        songID = entry.songID
        title = entry.title
        artist = entry.artist
        artworkURL = entry.artworkURL
        previewURL = entry.previewURL
        appleMusicURL = entry.appleMusicURL
        memo = entry.shareMemo ? entry.memo : ""
        postedAt = entry.createdAt
    }

    var day: Date? { DayKey.date(from: dayKey) }
}

extension Array {
    /// size 件ずつに分ける（CloudKit に一度に渡す件数を抑えるため）
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
