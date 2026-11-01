import CloudKit
import Combine
import CryptoKit
import SwiftData
import UIKit

/// フレンドとの音楽の共有（CloudKit の公開データベース）。
///
/// 利用者の iCloud ストレージを使わないよう、すべて公開 DB に置く（iCloud が満杯の人でも使える）。
/// 公開 DB は誰でも読めるので、「鍵」を知っている人だけが読める形にする：
/// - 利用者ごとにランダムな鍵（secret）を作り、投稿のレコード名を "s-<鍵>-<日付>" にする。
///   Post に検索用の索引は付けないので、鍵を知らない人は投稿を探し出せない。
/// - フレンドコード（8文字）のレコード "FriendCode"（レコード名 = コード）にはニックネーム・アイコン・公開鍵だけを置く。
///   コードを知っていても、鍵は分からない。
/// - フレンドは「申請 → 承認」でなる。申請する人は、相手の「郵便受け」（レコード名 "r-<相手のコード>-<番号>" の 64 枠）に
///   自分のコードと、相手の公開鍵でしか開けない形にした自分の鍵を置く。相手が承認すると、相手も同じように鍵を届けてくれる。
///   郵便受けもレコード名を指定して読むだけで、検索はしない。
/// - どのレコードにも検索用の索引を付けない（付けると他人のコードや投稿を探し出せてしまう）。
/// - フレンドをやめる・ブロックしたら、自分の鍵とコードを作り直し、残りのフレンドにだけ新しい鍵を届ける。
@MainActor
final class SocialStore: ObservableObject {
    static let shared = SocialStore()

    static let containerID = "iCloud.com.taigayanai.watashitoongaku"
    static let inviteBaseURL = "https://taigayanai-git.github.io/WatashiToOngaku/add.html"
    /// タイムラインに出す期間（日）
    /// タイムラインで遡れる日数。Plus は「さらに読み込む」で30日ずつ、1年前まで遡れる
    static let freeTimelineDays = 14
    static let plusTimelineDays = 365
    private static let loadMoreDays = 30

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
    /// 届いたフレンド申請
    @Published private(set) var incomingRequests: [PendingFriend] = []
    /// 自分が送って、承認を待っている申請
    @Published private(set) var outgoingRequests: [PendingFriend] = []
    /// ブロックした人（設定のブロックリスト）
    @Published private(set) var blockedUsers: [PendingFriend] = []
    @Published private(set) var timeline: [FriendPost] = []
    @Published private(set) var isRefreshing = false
    /// タイムラインに読み込んである日数（今日を含む）
    @Published private(set) var timelineDays = SocialStore.freeTimelineDays
    @Published private(set) var isLoadingMore = false
    /// 自分がいいねしたフレンドの投稿（レコード名）
    @Published private(set) var likedByMe: Set<String> = []
    /// 自分の投稿（日付）にいいねしたフレンド
    @Published private(set) var likers: [String: [Friend]] = [:]
    /// 公式アカウント（公開されていれば）
    @Published private(set) var official: Friend?
    /// 公式アカウント（開発者）とフレンドになっているか。中では一方通行のフォローとして扱う
    @Published private(set) var followsOfficial = false
    /// この端末が公式アカウントの持ち主で、自分の曲を公式として公開しているか
    @Published private(set) var publishesOfficial = false
    /// 持ち主：公式アカウントとフレンドになった人（投稿を読む鍵を届けてくれた人）
    @Published private(set) var followers: [Friend] = []
    @Published var lastError: String?

    var inviteURL: URL? {
        friendCode.isEmpty ? nil : URL(string: "\(Self.inviteBaseURL)?c=\(friendCode)")
    }

    private var publicDB: CKDatabase { CKContainer(identifier: Self.containerID).publicCloudDatabase }

    // MARK: - 端末に残す情報（iCloud の Key-Value にも控えて、入れ直しても引き継ぐ）

    private let local = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default

    /// 開発用：シミュレータでは iCloud の Key-Value を使わない。
    /// 実機と同じ Apple アカウントでサインインしても、別の人としてフレンド機能を試せるようにする
    #if DEBUG && targetEnvironment(simulator)
    private let usesCloud = false
    #else
    private let usesCloud = true
    #endif

    private func value(_ key: String) -> Any? { local.object(forKey: key) ?? (usesCloud ? cloud.object(forKey: key) : nil) }
    private func set(_ value: Any?, _ key: String) {
        local.set(value, forKey: key)
        guard usesCloud else { return }
        cloud.set(value, forKey: key)
        cloud.synchronize()
    }

    private var secret: String {
        get { value("social_secret") as? String ?? "" }
        set { set(newValue, "social_secret") }
    }
    /// フレンド（コード・相手の鍵・相手の iCloud 利用者）。相手が承認して鍵を届けてくれたら加わる
    private var links: [FriendLink] {
        get { (value("social_links") as? Data).flatMap { try? JSONDecoder().decode([FriendLink].self, from: $0) } ?? [] }
        set { set(try? JSONEncoder().encode(newValue), "social_links") }
    }
    /// 自分が申請して、承認を待っている相手のコード
    private var outgoingCodes: [String] {
        get { value("social_outgoing") as? [String] ?? [] }
        set { set(newValue, "social_outgoing") }
    }
    /// 届いた申請（承認するまで相手の鍵は使わない）。郵便受けの既読と同じく端末にだけ残す
    private var incomingLinks: [FriendLink] {
        get { local.data(forKey: "social_incoming").flatMap { try? JSONDecoder().decode([FriendLink].self, from: $0) } ?? [] }
        set { local.set(try? JSONEncoder().encode(newValue), forKey: "social_incoming") }
    }
    /// 鍵を届け合うための鍵ペア。公開鍵を FriendCode に置き、届いた鍵はこの秘密鍵でしか開けない
    private var keyPair: Curve25519.KeyAgreement.PrivateKey {
        if let text = value("social_privateKey") as? String, let data = Data(base64Encoded: text),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) { return key }
        let key = Curve25519.KeyAgreement.PrivateKey()
        set(key.rawRepresentation.base64EncodedString(), "social_privateKey")
        return key
    }
    private var blocked: Set<String> {
        get { Set(value("social_blocked") as? [String] ?? []) }
        set { set(Array(newValue), "social_blocked"); updateBlockedUsers() }
    }
    /// ブロックした人のニックネーム（ブロックリストに出す。相手のコードはもう読めないことがあるので、ブロックしたときに控える）
    private var blockedNames: [String: String] {
        get { value("social_blockedNames") as? [String: String] ?? [:] }
        set { set(newValue, "social_blockedNames") }
    }
    /// 自分のアイコン（128px の JPEG）。端末にも置いておき、コードを作り直したときにも付け直す
    private var myAvatarFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("my-avatar.jpg")
    }

    /// いいねしたフレンドの投稿（レコード名）。コードを作り直したときに付け直し、やめるときに消すために控える
    private var likedPosts: Set<String> {
        get { Set(value("social_liked") as? [String] ?? []) }
        set {
            // 1年より前の投稿へのいいねは控えから外す（Key-Value ストレージの容量を抑える）
            let oldest = DayKey.string(from: Calendar.current.date(byAdding: .day, value: -Self.plusTimelineDays, to: Date()) ?? Date())
            set(newValue.filter { String($0.suffix(10)) >= oldest }.sorted(), "social_liked")
        }
    }

    private var handledRequests: Set<String> {
        get { Set(local.stringArray(forKey: "social_handledRequests") ?? []) }
        set { local.set(Array(newValue), forKey: "social_handledRequests") }
    }

    // MARK: - 公式アカウント
    //
    // 開発者と誰でもフレンドになれる。画面ではふつうのフレンドと同じに見せるが、中では一方通行のフォローで、
    // 承認も人数の上限もない（ふつうのフレンドの申請の枠は 64 しかなく、持ち主が全員の投稿を読むことになるため）。
    // - プロフィールはレコード "official-profile"、投稿は "o-<日付>"（誰でも読める。中身は公開してよいものだけ）
    // - 公式として書けるのは、開発用ビルドで「公式アカウントの持ち主」にした端末（iCloud の Key-Value に控える）だけ
    // - フォローする側は、投稿を置いた iCloud 利用者がプロフィールを置いた人と同じかを確かめる
    // - フォローすると、公式の「郵便受け」（"of-<番号>"）に自分のコードと鍵（公式の公開鍵でしか開けない）を置く。
    //   持ち主はこれでフォロワーの投稿を読み、公式としていいねできる（"l-<投稿>-OFFICIAL"）
    // - 公式の投稿へのいいねは OfficialLike（"ol-<日付>-<ランダム>"）に置き、持ち主は日付で検索する。
    //   索引を付けるのはこの型の dayKey だけ（公式の投稿はもともと公開なので、他人の投稿を探し出せることにはならない）

    /// フォロー用のコード。ふつうのフレンドコードには O と I を使わないので、重ならない
    static let officialCode = "OFFICIAL"
    private static let officialProfileID = CKRecord.ID(recordName: "official-profile")

    private static func officialPostID(_ dayKey: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "o-\(dayKey)")
    }

    /// 画面に出すフレンド：ふつうのフレンドと、フレンドになった公式アカウント（開発者）。
    /// 公式の持ち主とふつうのフレンドでもあるなら、公式のほうは重ねて出さない
    var allFriends: [Friend] {
        guard followsOfficial, !isOfficialOwner, let official,
              !links.contains(where: { $0.creator == officialCreator }) else { return friends }
        return [official] + friends
    }

    /// 公式アカウントの持ち主の端末か（開発用ビルドの設定で決める）
    var isOfficialOwner: Bool {
        get { value("official_owner") as? Bool ?? false }
        set { set(newValue, "official_owner"); objectWillChange.send() }
    }

    /// 公式のプロフィールを置いた iCloud 利用者（これと違う人が置いた投稿は出さない）
    private var officialCreator: String?

    /// 公式の公開鍵（フォロワーが鍵を届けるのに使う）
    private var officialPublicKey: Data?

    /// フォローしたときに鍵を置いた郵便受けの枠
    private var officialFollowSlot: String? {
        get { value("official_followSlot") as? String }
        set { set(newValue, "official_followSlot") }
    }
    /// 公式の投稿に付けたいいね：日付 → レコード名
    private var officialLikes: [String: String] {
        get { value("official_likes") as? [String: String] ?? [:] }
        set { set(newValue, "official_likes") }
    }

    private var officialStamps: [String: String] {
        get { local.dictionary(forKey: "official_uploaded") as? [String: String] ?? [:] }
        set { local.set(newValue, forKey: "official_uploaded") }
    }

    func setFollowsOfficial(_ follows: Bool) async {
        followsOfficial = follows
        set(follows, "official_follow")
        if follows {
            await refresh()
        } else {
            timeline.removeAll { $0.friend.isOfficial }
            await withdrawFromOfficial()
        }
    }

    /// 公式の郵便受けに、自分のコードと鍵を置く（コードを作り直したときは同じ枠を書き換える）
    private func sendKeyToOfficial() async {
        guard followsOfficial, !isOfficialOwner, state == .ready, let publicKey = officialPublicKey,
              let payload = try? Self.seal(secret, from: friendCode, to: Self.officialCode, publicKey: publicKey) else { return }
        let fields: [String: CKRecordValue] = ["fromCode": friendCode as NSString, "payload": payload as NSData]
        if let slot = officialFollowSlot {
            let record = CKRecord(recordType: "FriendRequest", recordID: CKRecord.ID(recordName: slot))
            for (key, value) in fields { record[key] = value }
            if (try? await save(record)) != nil { return }
        }
        let slot = await claimSlot(prefix: "of-", type: "FriendRequest", fields: fields)
        // 置いているあいだにフレンドをやめていたら、置いた鍵をすぐ消す
        guard followsOfficial else {
            if let slot { _ = try? await publicDB.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: slot)]) }
            return
        }
        officialFollowSlot = slot
    }

    /// フォローをやめる・フレンド機能をやめる：公式に届けた鍵と、公式の投稿へのいいねを消す
    private func withdrawFromOfficial() async {
        let ids = ([officialFollowSlot].compactMap { $0 } + officialLikes.values).map { CKRecord.ID(recordName: $0) }
        guard !ids.isEmpty, let (_, deleted) = try? await publicDB.modifyRecords(saving: [], deleting: ids) else { return }
        // 1件でも消せなかったら（もう無いものは消えたとみなす）、控えを残して次の機会にやり直す
        let failed = ids.contains { id in
            guard case .failure(let error)? = deleted[id] else { return false }
            return (error as? CKError)?.code != .unknownItem
        }
        guard !failed else { return }
        officialFollowSlot = nil
        officialLikes = [:]
        likedByMe = likedByMe.filter { !$0.hasPrefix("o-") }
    }

    /// "<prefix><番号>" の枠のうち、空いている最初の枠に置く。誰かに先を越されたら次の枠へ
    private func claimSlot(prefix: String, type: String, fields: [String: CKRecordValue]) async -> String? {
        var start = 0
        while start < 5000 {
            let ids = (start..<start + 100).map { CKRecord.ID(recordName: "\(prefix)\($0)") }
            guard let found = try? await publicDB.records(for: ids, desiredKeys: []) else { return nil }
            for id in ids {
                if case .success? = found[id] { continue }
                let record = CKRecord(recordType: type, recordID: id)
                for (key, value) in fields { record[key] = value }
                if (try? await publicDB.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)) .flatMap({ try? $0.saveResults[id]?.get() }) != nil {
                    return id.recordName
                }
            }
            start += 100
        }
        return nil
    }

    /// 枠を順に読む（いくつかの prefix をまとめて）。100 枠まとめて空なら、その先は読まない
    private func readSlots(_ prefixes: [String]) async -> [String: [CKRecord]] {
        var result: [String: [CKRecord]] = [:]
        var pending = prefixes, start = 0
        while !pending.isEmpty, start < 5000 {
            let ids = pending.flatMap { prefix in (start..<start + 100).map { CKRecord.ID(recordName: "\(prefix)\($0)") } }
            var found: [CKRecord.ID: CKRecord] = [:]
            for chunk in ids.chunked(200) {
                guard let results = try? await publicDB.records(for: chunk) else { return result }
                for case let (id, .success(record)) in results { found[id] = record }
            }
            pending = pending.filter { prefix in
                let records = (start..<start + 100).compactMap { found[CKRecord.ID(recordName: "\(prefix)\($0)")] }
                result[prefix, default: []] += records
                return !records.isEmpty
            }
            start += 100
        }
        return result
    }

    /// 枠に置かれたコードが、そのコードの持ち主本人が置いたものか確かめて、フレンドの形にする
    private func verifiedSenders(_ records: [CKRecord]) async -> [(record: CKRecord, friend: Friend)] {
        let codes = Set(records.compactMap { $0["fromCode"] as? String }).subtracting(blocked)
        guard !codes.isEmpty, let owners = try? await publicDB.records(for: codes.map { CKRecord.ID(recordName: $0) },
                                                                      desiredKeys: ["nickname", "avatarVersion"]) else { return [] }
        return records.compactMap { record in
            guard let code = record["fromCode"] as? String, codes.contains(code),
                  case .success(let owner)? = owners[CKRecord.ID(recordName: code)],
                  owner.creatorUserRecordID?.recordName == record.creatorUserRecordID?.recordName else { return nil }
            let version = owner["avatarVersion"] as? Int ?? 0
            AvatarStore.shared.fetchIfNeeded(code: code, version: version, in: publicDB)
            return (record, Friend(code: code, nickname: owner["nickname"] as? String ?? S("フォロワー", "Follower", "팔로워"),
                                   secret: "", avatarVersion: version, isFollower: true))
        }
    }

    /// 持ち主：郵便受けからフォロワーと、その投稿を読む鍵を取り出す（フレンドでもある人はフレンドとして出す）
    private func loadFollowers() async {
        guard isOfficialOwner, publishesOfficial else { followers = []; return }
        let records = await readSlots(["of-"])["of-"] ?? []
        let friendCodes = Set(links.map(\.code))
        var seen = Set<String>()
        followers = await verifiedSenders(records).compactMap { item in
            guard !friendCodes.contains(item.friend.code), seen.insert(item.friend.code).inserted,
                  let payload = item.record["payload"] as? Data,
                  let secret = Self.open(payload, with: keyPair, from: item.friend.code, to: Self.officialCode) else { return nil }
            let friend = item.friend
            return Friend(code: friend.code, nickname: friend.nickname, secret: secret, avatarVersion: friend.avatarVersion, isFollower: true)
        }
    }

    /// 公式のプロフィールを読む
    private func loadOfficial() async {
        guard let results = try? await publicDB.records(for: [Self.officialProfileID], desiredKeys: ["nickname", "avatarVersion", "publicKey"]),
              case .success(let record)? = results[Self.officialProfileID] else {
            official = nil
            officialCreator = nil
            return
        }
        let version = record["avatarVersion"] as? Int ?? 0
        let code = Self.officialProfileID.recordName
        AvatarStore.shared.fetchIfNeeded(code: code, version: version, in: publicDB)
        officialCreator = record.creatorUserRecordID?.recordName
        officialPublicKey = record["publicKey"] as? Data
        official = Friend(code: code, nickname: record["nickname"] as? String ?? "Our Music", secret: "",
                          avatarVersion: version, isOfficial: true)
    }

    /// 持ち主：自分の曲を公式として公開する／やめる（やめると公式の投稿とプロフィールを消す）
    func setPublishesOfficial(_ publish: Bool) async {
        guard isOfficialOwner, state == .ready else { return }
        publishesOfficial = publish
        set(publish, "official_publish")
        if publish {
            await syncOfficial()
        } else {
            let ids = Set(localEntries.map(\.dayKey)).union(officialStamps.keys).map(Self.officialPostID) + [Self.officialProfileID]
            for chunk in ids.chunked(200) {
                _ = try? await publicDB.modifyRecords(saving: [], deleting: chunk)
            }
            officialStamps = [:]
            followers = []
        }
        await loadOfficial()
    }

    /// 持ち主：公式のプロフィール（ニックネームとアイコン）と、前回から変わった投稿を置く
    private func syncOfficial() async {
        guard isOfficialOwner, publishesOfficial, state == .ready, !isPreview else { return }
        let profile = (try? await publicDB.record(for: Self.officialProfileID))
            ?? CKRecord(recordType: "FriendCode", recordID: Self.officialProfileID)
        let publicKey = keyPair.publicKey.rawRepresentation
        if profile["nickname"] as? String != nickname || profile["avatarVersion"] as? Int ?? 0 != avatarVersion
            || profile["publicKey"] as? Data != publicKey {
            profile["nickname"] = nickname
            profile["publicKey"] = publicKey
            if avatarVersion == 0 {
                profile["avatar"] = nil
                profile["avatarVersion"] = nil
            } else if FileManager.default.fileExists(atPath: myAvatarFile.path) {
                profile["avatar"] = CKAsset(fileURL: myAvatarFile)
                profile["avatarVersion"] = avatarVersion
                AvatarStore.shared.storeOwn((try? Data(contentsOf: myAvatarFile)) ?? Data(), code: Self.officialProfileID.recordName,
                                            version: avatarVersion)
            }
            do { _ = try await save(profile) } catch {
                print("[Social] official profile failed: \(Self.describe(error))")
                return
            }
        }
        var stamps = officialStamps
        let changed = localEntries.filter { stamps[$0.dayKey] != Self.stamp($0) }
        for chunk in changed.chunked(200) {
            let saving = chunk.filter(\.shareSong).map { postRecord($0, id: Self.officialPostID($0.dayKey)) }
            let deleting = chunk.filter { !$0.shareSong }.map { Self.officialPostID($0.dayKey) }
            guard (try? await publicDB.modifyRecords(saving: saving, deleting: deleting, savePolicy: .allKeys)) != nil else { break }
            for entry in chunk { stamps[entry.dayKey] = Self.stamp(entry) }
        }
        officialStamps = stamps
    }

    // MARK: - はじめる

    /// 起動時：以前フレンド機能を使っていたら、読み込んで更新する
    func start() async {
        cloud.synchronize()
        updateBlockedUsers()
        followsOfficial = value("official_follow") as? Bool ?? false
        publishesOfficial = isOfficialOwner && (value("official_publish") as? Bool ?? false)
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
            // アプリを入れ直したら、iCloud に置いてある自分の投稿から記録を戻す（入れるたびに1回）
            if !local.bool(forKey: "social_restoredOnce") {
                let count = await restoreFromCloud()
                print("[Social] iCloud から \(count) 日分の記録を戻しました")
                local.set(true, forKey: "social_restoredOnce")
            }
            step = "upload"
            await uploadAll()
            await refresh()
        } catch {
            print("[Social] setUp failed at \(step): \(Self.describe(error))")
            state = .unavailable(S("iCloud に接続できませんでした。", "Couldn't connect to iCloud.")
                                 + "\n(\(step)) " + Self.describe(error))
        }
    }

    /// コード → ニックネーム・公開鍵 の対応表を置く（鍵は置かない）
    private func publishFriendCode() async throws {
        let id = CKRecord.ID(recordName: friendCode)
        let record = (try? await publicDB.record(for: id)) ?? CKRecord(recordType: "FriendCode", recordID: id)
        record["secret"] = nil
        record["publicKey"] = keyPair.publicKey.rawRepresentation
        record["nickname"] = nickname
        // アイコンは版が変わったときだけ付け直す（毎回アップロードしない）
        if avatarVersion > 0, (record["avatarVersion"] as? Int) != avatarVersion,
           FileManager.default.fileExists(atPath: myAvatarFile.path) {
            record["avatar"] = CKAsset(fileURL: myAvatarFile)
            record["avatarVersion"] = avatarVersion
        } else if avatarVersion == 0, record["avatarVersion"] != nil {
            // アイコンをはずした
            record["avatar"] = nil
            record["avatarVersion"] = nil
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

    /// アイコンの写真をはずす（初期アイコンに戻す）
    func removeAvatar() async -> Bool {
        guard state == .ready else { return false }
        let previous = avatarVersion
        avatarVersion = 0
        set(0, "social_avatarVersion")
        do {
            try await publishFriendCode()
        } catch {
            avatarVersion = previous
            set(previous, "social_avatarVersion")
            lastError = Self.describe(error)
            return false
        }
        try? FileManager.default.removeItem(at: myAvatarFile)
        await syncOfficial()
        return true
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
            await syncOfficial()
            return
        }
        do {
            _ = try await save(postRecord(entry, id: id))
            uploadedStamps[entry.dayKey] = Self.stamp(entry)
        } catch {
            lastError = Self.describe(error)
        }
        await syncOfficial()
    }

    /// 投稿のレコードを作る（自分だけが書くので、サーバーの内容を読まずに丸ごと上書きする）
    private func postRecord(_ entry: SongEntry, id: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: "Post", recordID: id)
        record["dayKey"] = entry.dayKey
        record["songID"] = entry.songID
        record["title"] = entry.title
        record["artist"] = entry.artistDisplayName
        record["albumTitle"] = entry.albumTitle
        record["artworkURL"] = entry.artworkURL
        record["previewURL"] = entry.previewURL
        record["appleMusicURL"] = entry.appleMusicURL
        record["memo"] = entry.shareMemo ? entry.memo : ""
        record["clipStart"] = entry.clipStart
        record["postedAt"] = entry.createdAt
        return record
    }

    func deletePost(dayKey: String) async {
        guard state == .ready else { return }
        _ = try? await publicDB.modifyRecords(saving: [], deleting: [postID(secret: secret, dayKey: dayKey)])
        uploadedStamps[dayKey] = nil
        if isOfficialOwner, officialStamps[dayKey] != nil {
            _ = try? await publicDB.modifyRecords(saving: [], deleting: [Self.officialPostID(dayKey)])
            officialStamps[dayKey] = nil
        }
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
        [entry.songID, entry.artistDisplayName, entry.memo, "\(entry.shareSong)", "\(entry.shareMemo)", "\(entry.createdAt.timeIntervalSince1970)",
         entry.clipStart.map { "\($0)" } ?? "-"].joined(separator: "|")
    }

    /// iCloud に置いた自分の投稿から、この端末にない日の記録を戻す（アプリを入れ直したときなど）。
    /// 共有していなかった日と、フレンドに見せていなかったメモは iCloud にないので戻せない。戻した件数を返す
    func restoreFromCloud() async -> Int {
        guard state == .ready else { return 0 }
        let context = AppContainer.shared.mainContext
        var existing = Set(localEntries.map(\.dayKey))
        let start = Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
        let ids = Self.dayKeys(from: start, to: Date()).filter { !existing.contains($0) }.map { postID(secret: secret, dayKey: $0) }
        var stamps = uploadedStamps
        var restored = 0
        for chunk in ids.chunked(200) {
            guard let found = try? await publicDB.records(for: chunk) else { continue }
            for case let (_, .success(record)) in found {
                guard let dayKey = record["dayKey"] as? String, !existing.contains(dayKey) else { continue }
                let entry = SongEntry(dayKey: dayKey, song: PickedSong(
                    id: record["songID"] as? String ?? "",
                    title: record["title"] as? String ?? "",
                    artist: record["artist"] as? String ?? "",
                    albumTitle: record["albumTitle"] as? String ?? "",
                    artworkURL: record["artworkURL"] as? String ?? "",
                    previewURL: record["previewURL"] as? String,
                    appleMusicURL: record["appleMusicURL"] as? String,
                    clipStart: record["clipStart"] as? Double))
                entry.memo = record["memo"] as? String ?? ""
                entry.createdAt = record["postedAt"] as? Date ?? record.creationDate ?? Date()
                entry.updatedAt = entry.createdAt
                context.insert(entry)
                existing.insert(dayKey)
                // iCloud と同じ内容なので、置き直さない
                stamps[dayKey] = Self.stamp(entry)
                restored += 1
            }
        }
        try? context.save()
        uploadedStamps = stamps
        return restored
    }

    /// 前回から変わった記録を置き直す（アーティストの正式名称が分かったときなど）
    func uploadChanges() async {
        guard state == .ready else { return }
        await uploadAll()
        await syncOfficial()
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

    // MARK: - フレンドの追加（申請と承認）

    enum AddResult { case requested, becameFriends, followedOfficial }

    /// フレンドコードで申請する。相手が承認するとフレンドになる（相手からも申請が届いていれば、すぐにフレンドになる）
    func addFriend(code raw: String) async -> AddResult? {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard state == .ready else { lastError = S("先にニックネームを決めてください", "Set your nickname first"); return nil }
        if code == Self.officialCode {
            await loadOfficial()
            // 開発者とはもうフレンド（公式としても、ふつうのフレンドとしても）
            guard !followsOfficial, !isOfficialOwner,
                  !links.contains(where: { $0.creator == officialCreator }) else {
                lastError = S("開発者とはすでにフレンドです", "You're already friends with the developer", "개발자와 이미 친구입니다")
                return nil
            }
            guard official != nil else {
                lastError = S("公式アカウントはまだ準備中です", "The official account isn't available yet", "공식 계정은 아직 준비 중입니다")
                return nil
            }
            await setFollowsOfficial(true)
            return .followedOfficial
        }
        guard code.count == 8 else { lastError = S("フレンドコードは8文字です", "Friend codes are 8 characters"); return nil }
        guard code != friendCode else { lastError = S("自分のコードです", "That's your own code"); return nil }
        guard !blocked.contains(code) else { lastError = S("ブロック中のユーザーです", "You've blocked this user"); return nil }
        guard !links.contains(where: { $0.code == code }) else { lastError = S("すでにフレンドです", "You're already friends"); return nil }
        if let request = incomingRequests.first(where: { $0.code == code }) {
            return await approve(request) ? .becameFriends : nil
        }
        guard await sendKey(to: code) else { return nil }
        if !outgoingCodes.contains(code) { outgoingCodes.append(code) }
        await refresh()
        return .requested
    }

    static func message(for result: AddResult) -> String {
        switch result {
        case .requested: return S("フレンド申請を送りました。相手が承認するとフレンドになります。",
                                  "Request sent. You'll become friends once they accept.")
        case .becameFriends: return S("フレンドになりました！", "You're now friends!")
        case .followedOfficial: return S("開発者とフレンドになりました！開発者の毎日の一曲がタイムラインに流れ、あなたが共有した曲も開発者に届きます。",
                                         "You're now friends with the developer! Their daily song will appear in your timeline, and your shared songs will reach them.",
                                         "개발자와 친구가 되었습니다! 개발자의 매일의 한 곡이 타임라인에 표시되고, 공유한 곡도 개발자에게 전달됩니다.")
        }
    }

    /// 招待リンク・QR コード（…/add.html?c=コード または watashitoongaku://add?c=コード）から申請する
    func addFriend(url: URL) async -> AddResult? {
        guard let code = Self.code(in: url) else {
            lastError = S("Our Music の招待リンクではありません", "This isn't an Our Music invite link")
            return nil
        }
        return await addFriend(code: code)
    }

    static func code(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "c" }?.value
    }

    /// 届いた申請を承認する：相手をフレンドに加え、自分の鍵を相手に届ける
    func approve(_ request: PendingFriend) async -> Bool {
        guard let link = incomingLinks.first(where: { $0.code == request.code }) else { return false }
        guard await sendKey(to: link.code) else { return false }
        incomingLinks.removeAll { $0.code == link.code }
        var current = links
        current.removeAll { $0.code == link.code }
        links = current + [link]
        await refresh()
        return true
    }

    /// 申請を断る（相手には知らせない）。block なら、この人からの申請はもう受け取らない
    func decline(_ request: PendingFriend, block: Bool) {
        incomingLinks.removeAll { $0.code == request.code }
        incomingRequests.removeAll { $0.code == request.code }
        if block { self.block(request.code, nickname: request.nickname) }
    }

    /// 送った申請を取り消す（相手の郵便受けに置いた鍵も消す）
    func cancelRequest(_ request: PendingFriend) async {
        outgoingCodes.removeAll { $0 == request.code }
        outgoingRequests.removeAll { $0.code == request.code }
        await withdrawKey(from: request.code)
    }

    /// 郵便受けの枠の数。送る側はコードから決まる枠から順に空きを探す
    private static let inboxSlots = 64

    private static func inboxID(_ code: String, _ slot: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "r-\(code)-\(slot)")
    }

    /// 相手の郵便受けに、自分のコードと鍵（相手の公開鍵でしか開けない形）を置く
    @discardableResult
    private func sendKey(to code: String, previousCode: String? = nil) async -> Bool {
        guard let profile = try? await publicDB.record(for: CKRecord.ID(recordName: code)) else {
            lastError = S("このコードのユーザーが見つかりません", "No user found for this code")
            return false
        }
        guard let publicKey = profile["publicKey"] as? Data,
              let payload = try? Self.seal(secret, from: friendCode, to: code, publicKey: publicKey) else {
            lastError = S("相手の Our Music が古いため申請できません。アップデートしてもらってください",
                          "Their Our Music is out of date. Ask them to update the app.")
            return false
        }
        let start = abs(friendCode.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.inboxSlots
        for offset in 0..<Self.inboxSlots {
            let id = Self.inboxID(code, (start + offset) % Self.inboxSlots)
            // 自分が前に置いた枠なら上書きする。他人の枠なら次へ
            let record: CKRecord
            if let existing = try? await publicDB.record(for: id) {
                guard existing.creatorUserRecordID?.recordName == CKCurrentUserDefaultName else { continue }
                record = existing
            } else {
                record = CKRecord(recordType: "FriendRequest", recordID: id)
            }
            record["fromCode"] = friendCode
            record["previousCode"] = previousCode
            record["payload"] = payload
            record["sentAt"] = Date()
            if (try? await save(record)) != nil { return true }
        }
        lastError = S("相手に申請を届けられませんでした", "Couldn't deliver the request")
        return false
    }

    /// 相手の郵便受けから、自分が置いた鍵を消す
    private func withdrawKey(from code: String) async {
        let ids = (0..<Self.inboxSlots).map { Self.inboxID(code, $0) }
        guard let found = try? await publicDB.records(for: ids, desiredKeys: ["fromCode"]) else { return }
        let mine = found.compactMap { id, result -> CKRecord.ID? in
            guard let record = try? result.get(), record.creatorUserRecordID?.recordName == CKCurrentUserDefaultName,
                  record["fromCode"] as? String == friendCode else { return nil }
            return id
        }
        if !mine.isEmpty { _ = try? await publicDB.modifyRecords(saving: [], deleting: mine) }
    }

    /// 自分の郵便受けを読む。
    /// - 申請した相手から鍵が届いた ＝ 承認された → フレンドに加える
    /// - フレンドがコードを作り直した（previousCode）→ 新しいコードと鍵に置き換える
    /// - それ以外 → 届いた申請として、承認を待つ
    /// 鍵を置いた人とコードの持ち主が同じ iCloud 利用者かを確かめて、他人のコードを名乗った申請は捨てる
    private func processFriendRequests() async {
        let ids = (0..<Self.inboxSlots).map { Self.inboxID(friendCode, $0) }
        guard let found = try? await publicDB.records(for: ids) else { return }
        var handled = handledRequests
        var received: [(record: CKRecord, from: String, stamp: String)] = []
        for case let (_, .success(record)) in found {
            let from = record["fromCode"] as? String ?? ""
            let stamp = "\(record.recordID.recordName)@\(record.modificationDate?.timeIntervalSince1970 ?? 0)"
            guard !from.isEmpty, from != friendCode, !handled.contains(stamp) else { continue }
            received.append((record, from, stamp))
        }
        guard !received.isEmpty,
              let owners = try? await publicDB.records(for: Array(Set(received.map { CKRecord.ID(recordName: $0.from) })),
                                                       desiredKeys: ["nickname"]) else { return }
        var current = links, outgoing = outgoingCodes, incoming = incomingLinks
        for item in received {
            handled.insert(item.stamp)
            let creator = item.record.creatorUserRecordID?.recordName ?? ""
            guard !blocked.contains(item.from),
                  case .success(let owner)? = owners[CKRecord.ID(recordName: item.from)],
                  owner.creatorUserRecordID?.recordName == creator,
                  let payload = item.record["payload"] as? Data,
                  let secret = Self.open(payload, with: keyPair, from: item.from, to: friendCode) else { continue }
            let link = FriendLink(code: item.from, secret: secret, creator: creator)
            if let previous = item.record["previousCode"] as? String {
                // やめたフレンドや、別の人からのコード更新は受け取らない
                guard let index = current.firstIndex(where: { $0.code == previous }), current[index].creator == creator else { continue }
                current[index] = link
            } else if let index = current.firstIndex(where: { $0.code == item.from }) {
                current[index] = link
            } else if outgoing.contains(item.from) {
                outgoing.removeAll { $0 == item.from }
                current.append(link)
            } else {
                incoming.removeAll { $0.code == item.from }
                incoming.append(link)
            }
        }
        handledRequests = handled
        links = current
        outgoingCodes = outgoing
        incomingLinks = incoming
    }

    // MARK: - 鍵の受け渡し（HPKE：相手の公開鍵で閉じ、相手の秘密鍵でしか開けない）

    private static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    /// 誰から誰へのものかを結び付けて、別の宛先に使い回せないようにする
    private static func info(from: String, to: String) -> Data { Data("OurMusic-key \(from)>\(to)".utf8) }

    private static func seal(_ secret: String, from: String, to: String, publicKey: Data) throws -> Data {
        let key = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        var sender = try HPKE.Sender(recipientKey: key, ciphersuite: ciphersuite, info: info(from: from, to: to))
        let sealed = try sender.seal(Data(secret.utf8))
        return sender.encapsulatedKey + sealed
    }

    private static func open(_ payload: Data, with key: Curve25519.KeyAgreement.PrivateKey, from: String, to: String) -> String? {
        guard payload.count > 32,
              var recipient = try? HPKE.Recipient(privateKey: key, ciphersuite: ciphersuite, info: info(from: from, to: to),
                                                  encapsulatedKey: Data(payload.prefix(32))),
              let opened = try? recipient.open(Data(payload.dropFirst(32))) else { return nil }
        return String(data: opened, encoding: .utf8)
    }

    // MARK: - タイムライン

    func refresh() async {
        guard state == .ready, !isRefreshing, !isPreview else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await processFriendRequests()

        // フレンド・申請の相手のニックネームとアイコンの版（画像は AvatarStore が必要なときだけ取る）
        let links = self.links, incoming = incomingLinks, outgoing = outgoingCodes
        let codes = Set(links.map(\.code) + incoming.map(\.code) + outgoing)
        let codeRecords = codes.isEmpty ? [:] : ((try? await publicDB.records(
            for: codes.map { CKRecord.ID(recordName: $0) }, desiredKeys: ["nickname", "avatarVersion"])) ?? [:])
        func profile(_ code: String) -> (nickname: String, version: Int)? {
            guard case .success(let record)? = codeRecords[CKRecord.ID(recordName: code)] else { return nil }
            let version = record["avatarVersion"] as? Int ?? 0
            AvatarStore.shared.fetchIfNeeded(code: code, version: version, in: publicDB)
            return (record["nickname"] as? String ?? S("フレンド", "Friend"), version)
        }
        let newFriends = links.compactMap { link in
            profile(link.code).map { Friend(code: link.code, nickname: $0.nickname, secret: link.secret, avatarVersion: $0.version) }
        }
        incomingRequests = incoming.compactMap { link in
            profile(link.code).map { PendingFriend(code: link.code, nickname: $0.nickname, avatarVersion: $0.version) }
        }
        outgoingRequests = outgoing.compactMap { code in
            profile(code).map { PendingFriend(code: code, nickname: $0.nickname, avatarVersion: $0.version) }
        }

        friends = newFriends.sorted { $0.nickname < $1.nickname }
        postCache = [:]
        await syncOfficial()
        await loadOfficial()
        // 開発者とふつうのフレンドでもあれば、その人にも「開発者」の印を付ける。
        // 持ち主の端末では、フレンドに開発者はいない（同じ Apple アカウントのテスト端末を開発者と見なさないように）
        if let creator = officialCreator, !isOfficialOwner {
            friends = friends.map { friend in
                var friend = friend
                friend.isDeveloper = links.first { $0.code == friend.code }?.creator == creator
                return friend
            }
        }
        if followsOfficial, officialFollowSlot == nil { await sendKeyToOfficial() }
        // 前にフレンドをやめたときに消せなかった鍵やいいねが残っていれば、もう一度消す
        if !followsOfficial, officialFollowSlot != nil || !officialLikes.isEmpty { await withdrawFromOfficial() }
        await loadFollowers()

        // 各フレンドの最近の投稿を、レコード名を指定して取り出す（検索はしない）
        // 更新するたびに最初の2週間に戻す（古い投稿は必要な人が「さらに読み込む」で取る）
        timelineDays = Self.freeTimelineDays
        let today = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(timelineDays - 1), to: today)!
        let days = Set(Self.dayKeys(from: start, to: today))
        let posts = await posts(from: start, to: today, includeAllOfMine: false)
        // 新しい日付を上に。同じ日付の中は新しい投稿を上に並べる
        timeline = posts.filter { days.contains($0.dayKey) }.sorted {
            $0.dayKey != $1.dayKey ? $0.dayKey > $1.dayKey : $0.postedAt > $1.postedAt
        }
        // いいねは、画面に出た投稿のカードがそれぞれ読み直す
        likesGeneration += 1
    }

    /// もっと前の投稿を読み込めるか（Plus は1年前まで）
    var canLoadMore: Bool {
        state == .ready && timelineDays < (PlusStore.shared.isPlus ? Self.plusTimelineDays : Self.freeTimelineDays)
    }

    /// タイムラインの下に、さらに前の30日分の投稿を足す（Plus）
    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isRefreshing else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let calendar = Calendar.current
        let today = Date()
        let newDays = min(timelineDays + Self.loadMoreDays, Self.plusTimelineDays)
        guard let end = calendar.date(byAdding: .day, value: -timelineDays, to: today),
              let start = calendar.date(byAdding: .day, value: -(newDays - 1), to: today) else { return }
        let older = await posts(from: start, to: end, includeAllOfMine: false).sorted {
            $0.dayKey != $1.dayKey ? $0.dayKey > $1.dayKey : $0.postedAt > $1.postedAt
        }
        let known = Set(timeline.map(\.id))
        let added = older.filter { !known.contains($0.id) }
        timeline += added
        timelineDays = newDays
    }

    // MARK: - いいね

    /// いいねは "l-<投稿のレコード名>-<いいねした人のコード>" に置く。
    /// 投稿の鍵を知っているフレンドにしか場所が分からず、投稿した人は自分のフレンドのコードで探す（検索はしない）
    /// 公式の投稿のいいねを一度に数える上限（超えたら「99+」）
    static let officialLikeLimit = 99

    /// タイムラインを更新するたびに増える。カードはこれが変わったら自分のいいねを読み直す
    @Published private(set) var likesGeneration = 0
    /// いいねが多すぎて数えきれなかった自分の投稿（日付）
    @Published private(set) var likeOverflow: Set<String> = []
    private var pendingLikes: [FriendPost] = []
    private var likesFlush: Task<Void, Never>?

    /// 画面に出た投稿のいいねを読む。少しのあいだに出たカードの分をまとめて読む
    func requestLikes(for post: FriendPost) {
        guard state == .ready, !isPreview else { return }
        pendingLikes.append(post)
        guard likesFlush == nil else { return }
        likesFlush = Task {
            try? await Task.sleep(for: .milliseconds(200))
            let batch = pendingLikes
            pendingLikes = []
            likesFlush = nil
            await fetchLikes(for: batch)
        }
    }

    private static func likeID(post: String, code: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "l-\(post)-\(code)")
    }

    private func likeRecord(post: String, code: String? = nil) -> CKRecord {
        let record = CKRecord(recordType: "Like", recordID: Self.likeID(post: post, code: code ?? friendCode))
        record["likedAt"] = Date()
        return record
    }

    /// 投稿にいいねする／取り消す。
    /// フレンドの投稿には自分のコードで、公式の持ち主がフォロワーの投稿に付けるときは公式（OFFICIAL）として付ける。
    /// 公式の投稿へのいいねは、日付で検索できる OfficialLike に置く
    func toggleLike(_ post: FriendPost) async {
        guard state == .ready, !post.friend.isMe else { return }
        let liking = !likedByMe.contains(post.id)
        if liking { likedByMe.insert(post.id) } else { likedByMe.remove(post.id) }
        guard !isPreview else { return }
        do {
            if post.friend.isOfficial {
                if liking {
                    let record = CKRecord(recordType: "OfficialLike",
                                          recordID: CKRecord.ID(recordName: "ol-\(post.dayKey)-\(Self.random(12))"))
                    record["dayKey"] = post.dayKey
                    record["fromCode"] = friendCode
                    record["likedAt"] = Date()
                    _ = try await save(record)
                    officialLikes[post.dayKey] = record.recordID.recordName
                } else if let slot = officialLikes[post.dayKey] {
                    _ = try await publicDB.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: slot)])
                    officialLikes[post.dayKey] = nil
                }
            } else if post.friend.isFollower {
                if liking {
                    _ = try await save(likeRecord(post: post.id, code: Self.officialCode))
                } else {
                    _ = try await publicDB.modifyRecords(saving: [], deleting: [Self.likeID(post: post.id, code: Self.officialCode)])
                }
            } else if liking {
                _ = try await save(likeRecord(post: post.id))
                likedPosts.insert(post.id)
            } else {
                _ = try await publicDB.modifyRecords(saving: [], deleting: [Self.likeID(post: post.id, code: friendCode)])
                likedPosts.remove(post.id)
            }
        } catch {
            // 届かなかったら元に戻す
            if liking { likedByMe.remove(post.id) } else { likedByMe.insert(post.id) }
            lastError = Self.describe(error)
        }
    }

    /// 投稿のいいねを読む。フレンドの投稿は自分がいいねしたか、自分の投稿は誰がいいねしたか。
    /// 自分の投稿へのいいねは、置いた iCloud 利用者がそのコードのフレンド本人かを確かめる（鍵を知る別のフレンドのなりすましを防ぐ）
    private func fetchLikes(for posts: [FriendPost]) async {
        guard state == .ready, !isPreview, !posts.isEmpty else { return }
        var links = self.links
        var friendsByCode = Dictionary(friends.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        // フォローしている公式からのいいねも、フレンドと同じように確かめる
        if followsOfficial, !isOfficialOwner, let official, let creator = officialCreator {
            links.append(FriendLink(code: Self.officialCode, secret: "", creator: creator))
            friendsByCode[Self.officialCode] = official
        }
        // いいねのレコード名 → (投稿, 自分の投稿ならいいねしたフレンド)
        var targets: [CKRecord.ID: (post: FriendPost, link: FriendLink?)] = [:]
        for post in posts where !post.friend.isOfficial {
            if post.friend.isMe {
                let name = postID(secret: secret, dayKey: post.dayKey).recordName
                for link in links { targets[Self.likeID(post: name, code: link.code)] = (post, link) }
            } else {
                let code = post.friend.isFollower ? Self.officialCode : friendCode
                targets[Self.likeID(post: post.id, code: code)] = (post, nil)
            }
        }
        // 持ち主：自分の投稿（＝公式の投稿）へのいいねを日付で検索する（多すぎるときは上限まで）
        var officialLikers: [String: [Friend]] = [:]
        var overflow = likeOverflow
        if isOfficialOwner, publishesOfficial {
            for dayKey in posts.filter(\.friend.isMe).map(\.dayKey) {
                let query = CKQuery(recordType: "OfficialLike", predicate: NSPredicate(format: "dayKey == %@", dayKey))
                guard let (results, cursor) = try? await publicDB.records(matching: query, desiredKeys: ["fromCode"],
                                                                         resultsLimit: Self.officialLikeLimit) else { continue }
                officialLikers[dayKey] = await verifiedSenders(results.compactMap { try? $0.1.get() }).map(\.friend)
                if cursor != nil { overflow.insert(dayKey) } else { overflow.remove(dayKey) }
            }
        }
        var found: [CKRecord.ID: CKRecord] = [:]
        for chunk in Array(targets.keys).chunked(200) {
            guard let results = try? await publicDB.records(for: chunk, desiredKeys: []) else { return }
            for case let (id, .success(record)) in results { found[id] = record }
        }
        var liked = likedByMe, likers = self.likers
        for post in posts {
            if post.friend.isMe { likers[post.dayKey] = nil } else { liked.remove(post.id) }
            // 公式の投稿へのいいねは、置いた枠を端末に控えてある
            if post.friend.isOfficial, officialLikes[post.dayKey] != nil { liked.insert(post.id) }
        }
        for (dayKey, friends) in officialLikers {
            for friend in friends where !(likers[dayKey] ?? []).contains(where: { $0.code == friend.code }) {
                likers[dayKey, default: []].append(friend)
            }
        }
        for (id, target) in targets {
            guard let record = found[id] else { continue }
            if let link = target.link {
                guard record.creatorUserRecordID?.recordName == link.creator, let friend = friendsByCode[link.code] else { continue }
                likers[target.post.dayKey, default: []].append(friend)
            } else {
                liked.insert(target.post.id)
            }
        }
        self.likedByMe = liked
        self.likers = likers.mapValues { $0.sorted { $0.nickname < $1.nickname } }
        likeOverflow = overflow
        // 確かめた投稿は、iCloud の状態に合わせて控えを直す（別の端末で取り消したいいねを付け直さないように）
        let checked = Set(posts.filter { !$0.friend.isMe && !$0.friend.isOfficial && !$0.friend.isFollower }.map(\.id))
        let saved = likedPosts.subtracting(checked).union(liked.intersection(checked))
        if saved != likedPosts { likedPosts = saved }
    }

    // MARK: - 期間の投稿（みんなのプレイリスト）

    /// レコード名 → 投稿（無ければ nil）。タイムラインを更新するたびに空にする
    private var postCache: [String: FriendPost?] = [:]

    private var me: Friend {
        Friend(code: friendCode, nickname: nickname, secret: secret, avatarVersion: avatarVersion, isMe: true,
               isDeveloper: isOfficialOwner)
    }

    /// 期間内の、フレンドと自分の投稿。
    /// includeAllOfMine なら自分の記録は共有していない日の曲も入れる（自分だけが見るプレイリスト用）
    func posts(from start: Date, to end: Date, includeAllOfMine: Bool = true) async -> [FriendPost] {
        let days = Self.dayKeys(from: start, to: min(end, Date()))
        var result: [FriendPost] = []
        if state == .ready {
            for friend in friends + followers {
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
            result += await officialPosts(days: days)
        }
        let keys = Set(days)
        let mine = localEntries.filter { keys.contains($0.dayKey) && (includeAllOfMine || $0.shareSong) }
        result += mine.map { FriendPost(entry: $0, me: me) }
        return result
    }

    /// フォローしている公式アカウントの投稿（持ち主の端末では自分の投稿として出るので取らない）
    private func officialPosts(days: [String]) async -> [FriendPost] {
        guard followsOfficial, !isOfficialOwner, let official, let creator = officialCreator,
              // 公式の持ち主とフレンドなら、同じ曲がフレンドの投稿として出るので重ねて出さない
              !links.contains(where: { $0.creator == creator }) else { return [] }
        let ids = days.map(Self.officialPostID)
        for chunk in ids.filter({ postCache[$0.recordName] == nil }).chunked(200) {
            guard let found = try? await publicDB.records(for: chunk) else { continue }
            for id in chunk {
                let record = try? found[id]?.get()
                postCache[id.recordName] = record.flatMap {
                    $0.creatorUserRecordID?.recordName == creator ? FriendPost(record: $0, friend: official) : nil
                }
            }
        }
        return ids.compactMap { postCache[$0.recordName] ?? nil }
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

    // MARK: - スクリーンショット用のサンプル

    /// -uiPreview のときは iCloud に接続せず、サンプルのフレンドの投稿を出す
    private(set) var isPreview = false

    func loadPreview(entries: [SongEntry]) {
        isPreview = true
        nickname = "Sora"
        friendCode = "SORA2345"
        let people = [("Mio", "MIO23456"), ("Ken", "KEN23456"), ("Yui", "YUI23456")].map {
            Friend(code: $0.1, nickname: $0.0, secret: "", avatarVersion: 0)
        }
        friends = people
        let me = Friend(code: friendCode, nickname: nickname, secret: "", avatarVersion: 0, isMe: true)
        // 新しい日付から、自分と3人のフレンドの投稿を交互に並べる
        timeline = entries.sorted { $0.dayKey > $1.dayKey }.prefix(12).enumerated().map { index, entry in
            FriendPost(entry: entry, me: index % 4 == 0 ? me : people[index % 3])
        }
        state = .ready
    }

    // MARK: - フレンド解除・ブロック・通報

    /// ブロックする：この人からの申請を受け取らない。フレンドだったときは remove で鍵を作り直すので、もう投稿も見られない
    private func block(_ code: String, nickname: String) {
        blockedNames[code] = nickname
        blocked.insert(code)
    }

    /// ブロックを解除する。フレンドには戻らない（また申請してもらえば、承認してフレンドになれる）
    func unblock(_ user: PendingFriend) {
        blockedNames[user.code] = nil
        blocked.remove(user.code)
    }

    private func updateBlockedUsers() {
        let names = blockedNames
        blockedUsers = blocked.map { PendingFriend(code: $0, nickname: names[$0] ?? $0) }.sorted { $0.nickname < $1.nickname }
    }

    /// フレンドをやめる。自分の鍵とコードを作り直して、相手が読めないようにする
    func remove(_ friend: Friend, block: Bool) async {
        if block { self.block(friend.code, nickname: friend.nickname) }
        // 開発者のフレンド（持ち主の端末）は鍵を交わしていないので、ブロックして出さないだけにする
        if friend.isFollower {
            followers.removeAll { $0.code == friend.code }
            timeline.removeAll { $0.friend.code == friend.code }
            return
        }
        links.removeAll { $0.code == friend.code }
        friends.removeAll { $0.code == friend.code }
        timeline.removeAll { $0.friend.code == friend.code }
        await rotateIdentity()
    }

    private func rotateIdentity() async {
        let oldSecret = secret, oldCode = friendCode
        // 承認待ちの申請に置いた古い鍵は消して、新しいコードで送り直す
        for code in outgoingCodes { await withdrawKey(from: code) }
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
        // いいねを新しいコードで付け直す（古いコードのものは消す）
        let liked = Array(likedPosts)
        for chunk in liked.chunked(200) {
            _ = try? await publicDB.modifyRecords(saving: chunk.map { likeRecord(post: $0) },
                                                  deleting: chunk.map { Self.likeID(post: $0, code: oldCode) })
        }
        // 残っているフレンドに新しいコードと鍵を届ける
        for link in links { await sendKey(to: link.code, previousCode: oldCode) }
        for code in outgoingCodes { await sendKey(to: code) }
        // 公式に届けた鍵と、公式の投稿へのいいねも新しいコードに書き換える
        await sendKeyToOfficial()
        for name in officialLikes.values {
            let record = CKRecord(recordType: "OfficialLike", recordID: CKRecord.ID(recordName: name))
            record["fromCode"] = friendCode
            _ = try? await save(record)
        }
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

    // MARK: - フレンド機能をやめる

    /// iCloud に置いた自分のデータ（ニックネーム・アイコン・投稿・相手に届けた鍵）をすべて消して、使い始める前に戻す。
    /// 端末の記録とブロックリストは残す。消せなかったら false
    func leave() async -> Bool {
        guard state == .ready else { return false }
        for code in links.map(\.code) + outgoingCodes { await withdrawKey(from: code) }
        let dayKeys = Set(localEntries.map(\.dayKey)).union(uploadedStamps.keys)
        let ids = dayKeys.map { postID(secret: secret, dayKey: $0) } + likedPosts.map { Self.likeID(post: $0, code: friendCode) }
            + [CKRecord.ID(recordName: friendCode)]
        do {
            for chunk in ids.chunked(200) {
                _ = try await publicDB.modifyRecords(saving: [], deleting: chunk)
            }
        } catch {
            lastError = Self.describe(error)
            return false
        }
        if isOfficialOwner { await setPublishesOfficial(false) }
        await withdrawFromOfficial()
        local.removeObject(forKey: "social_uploaded_\(secret)")
        for key in ["social_nickname", "social_secret", "social_code", "social_avatarVersion", "social_privateKey",
                    "social_links", "social_outgoing", "social_liked"] {
            local.removeObject(forKey: key)
            if usesCloud { cloud.removeObject(forKey: key) }
        }
        if usesCloud { cloud.synchronize() }
        for key in ["social_incoming", "social_handledRequests", "social_restoredOnce"] {
            local.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: myAvatarFile)
        nickname = ""
        friendCode = ""
        avatarVersion = 0
        friends = []
        incomingRequests = []
        outgoingRequests = []
        timeline = []
        likedByMe = []
        likers = [:]
        timelineDays = Self.freeTimelineDays
        state = .notSetUp
        return true
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

/// フレンド・届いた申請の相手：コード、相手の鍵、相手の iCloud 利用者（コード更新のなりすまし防止に照合する）
struct FriendLink: Codable, Hashable {
    var code: String
    var secret: String
    var creator: String
}

/// 申請中・申請が届いた相手（まだ鍵は使わない）
struct PendingFriend: Identifiable, Hashable {
    let code: String
    let nickname: String
    var avatarVersion = 0
    var id: String { code }
}

struct Friend: Identifiable, Hashable {
    let code: String
    let nickname: String
    let secret: String
    var avatarVersion = 0
    var isMe = false
    var isOfficial = false
    /// 開発者本人（公式アカウントの持ち主）。公式アカウントと同じく「開発者」の印を付ける
    var isDeveloper = false
    /// 公式アカウントのフォロワー（持ち主の端末にだけ出る）
    var isFollower = false
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
    /// 流す30秒の始まり（秒）。nil なら Apple の試聴区間
    let clipStart: Double?
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
        clipStart = record["clipStart"] as? Double
        postedAt = record["postedAt"] as? Date ?? record.modificationDate ?? Date()
    }

    /// 自分の投稿（端末内の記録から、フレンドに見えている内容で作る）
    init(entry: SongEntry, me: Friend) {
        id = "me-" + entry.dayKey
        friend = me
        dayKey = entry.dayKey
        songID = entry.songID
        title = entry.title
        artist = entry.artistDisplayName
        artworkURL = entry.artworkURL
        previewURL = entry.previewURL
        appleMusicURL = entry.appleMusicURL
        memo = entry.shareMemo ? entry.memo : ""
        clipStart = entry.clipStart
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
