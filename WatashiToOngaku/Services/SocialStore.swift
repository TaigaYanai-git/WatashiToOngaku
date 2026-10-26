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
    /// 届いたフレンド申請
    @Published private(set) var incomingRequests: [PendingFriend] = []
    /// 自分が送って、承認を待っている申請
    @Published private(set) var outgoingRequests: [PendingFriend] = []
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
        record["clipStart"] = entry.clipStart
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
        [entry.songID, entry.memo, "\(entry.shareSong)", "\(entry.shareMemo)", "\(entry.createdAt.timeIntervalSince1970)",
         entry.clipStart.map { "\($0)" } ?? "-"].joined(separator: "|")
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

    enum AddResult { case requested, becameFriends }

    /// フレンドコードで申請する。相手が承認するとフレンドになる（相手からも申請が届いていれば、すぐにフレンドになる）
    func addFriend(code raw: String) async -> AddResult? {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard state == .ready else { lastError = S("先にニックネームを決めてください", "Set your nickname first"); return nil }
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
        if block { blocked.insert(request.code) }
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
        guard state == .ready, !isRefreshing else { return }
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

        // 各フレンドの最近の投稿を、レコード名を指定して取り出す（検索はしない）
        let today = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(Self.timelineDays - 1), to: today)!
        let days = Set(Self.dayKeys(from: start, to: today))
        let posts = await posts(from: start, to: today, includeAllOfMine: false)
        // 新しい日付を上に。同じ日付の中は新しい投稿を上に並べる
        timeline = posts.filter { days.contains($0.dayKey) }.sorted {
            $0.dayKey != $1.dayKey ? $0.dayKey > $1.dayKey : $0.postedAt > $1.postedAt
        }
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
        // 残っているフレンドに新しいコードと鍵を届ける
        for link in links { await sendKey(to: link.code, previousCode: oldCode) }
        for code in outgoingCodes { await sendKey(to: code) }
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
        artist = entry.artist
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
