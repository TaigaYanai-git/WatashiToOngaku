import CloudKit
import Combine
import SwiftData
import UIKit

/// フレンドとの音楽の共有（CloudKit）。
///
/// しくみ：
/// - 自分の投稿は自分の iCloud（非公開 DB）の "Songs" ゾーンに置き、ゾーン全体を CKShare で共有する。
///   共有はリンクを知っている人だけが読める（publicPermission = .readOnly）。招待リンク・QR はこの URL。
/// - フレンドコード（8桁）は公開 DB の "FriendCode" レコード（レコード名 = コード）に共有 URL を載せて引けるようにする。
/// - 相手の共有を受け入れたら、公開 DB に "FriendRequest"（宛先コード・自分の共有 URL）を置く。
///   相手のアプリはそれを見つけて自動で受け入れるので、お互いにフレンドになる。
/// - フレンドの投稿は共有 DB の各ゾーンにある。タイムラインはそれを日時順に並べる。
@MainActor
final class SocialStore: ObservableObject {
    static let shared = SocialStore()

    static let containerID = "iCloud.com.taigayanai.watashitoongaku"
    private static let zoneName = "Songs"
    private static let profileRecordName = "profile"

    enum State: Equatable {
        case notSetUp          // ニックネーム未設定（フレンド機能を使っていない）
        case unavailable(String)
        case ready
    }

    @Published private(set) var state: State = .notSetUp
    @Published private(set) var nickname = ""
    @Published private(set) var friendCode = ""
    @Published private(set) var shareURL: URL?
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var timeline: [FriendPost] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    private var container: CKContainer { CKContainer(identifier: Self.containerID) }
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName) }

    private let defaults = UserDefaults.standard
    private var blocked: Set<String> {
        get { Set(defaults.stringArray(forKey: "social_blocked") ?? []) }
        set { defaults.set(Array(newValue), forKey: "social_blocked") }
    }
    private var handledRequests: Set<String> {
        get { Set(defaults.stringArray(forKey: "social_handledRequests") ?? []) }
        set { defaults.set(Array(newValue), forKey: "social_handledRequests") }
    }

    var isEnabled: Bool { defaults.bool(forKey: "social_enabled") }

    // MARK: - はじめる

    /// 起動時：以前フレンド機能を使っていたら、プロフィールを読み込んで更新する
    func start() async {
        guard isEnabled else { state = .notSetUp; return }
        await setUp(nickname: nil)
    }

    /// ニックネームを決めてフレンド機能を使い始める（2回目以降は nickname = nil で読み込みだけ）
    func setUp(nickname newName: String?) async {
        do {
            guard try await container.accountStatus() == .available else {
                state = .unavailable(S("iCloud にサインインすると、フレンド機能を使えます。「設定」アプリで iCloud にサインインしてください。",
                                       "Sign in to iCloud in the Settings app to use friends."))
                return
            }
            _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

            // プロフィール（ニックネームとフレンドコード）
            let profileID = CKRecord.ID(recordName: Self.profileRecordName, zoneID: zoneID)
            let profile = (try? await privateDB.record(for: profileID)) ?? CKRecord(recordType: "Profile", recordID: profileID)
            if let newName { profile["nickname"] = newName }
            if (profile["code"] as? String ?? "").isEmpty { profile["code"] = Self.makeCode() }
            let saved = try await save(profile, in: privateDB)
            nickname = saved["nickname"] as? String ?? ""
            friendCode = saved["code"] as? String ?? ""

            // ゾーン全体の共有（リンクを知っている人は読める）
            let share = try await zoneShare()
            shareURL = share.url

            // フレンドコード → 共有リンク の対応表
            if let url = share.url {
                let codeRecord = (try? await publicDB.record(for: CKRecord.ID(recordName: friendCode)))
                    ?? CKRecord(recordType: "FriendCode", recordID: CKRecord.ID(recordName: friendCode))
                codeRecord["shareURL"] = url.absoluteString
                codeRecord["nickname"] = nickname
                _ = try await save(codeRecord, in: publicDB)
            }

            defaults.set(true, forKey: "social_enabled")
            state = .ready
            await uploadAll()
            await refresh()
        } catch {
            state = .unavailable(S("iCloud に接続できませんでした。", "Couldn't connect to iCloud.") + "\n" + error.localizedDescription)
        }
    }

    private func zoneShare() async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await privateDB.record(for: shareID) as? CKShare { return existing }
        let share = CKShare(recordZoneID: zoneID)
        share.publicPermission = .readOnly
        share[CKShare.SystemFieldKey.title] = S("私と音楽のフレンド招待", "Me & Music friend invite")
        return try await save(share, in: privateDB) as! CKShare
    }

    /// 紛らわしい文字（0/O, 1/I）を除いた8桁
    private static func makeCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in chars.randomElement()! })
    }

    // MARK: - 投稿（自分の曲を共有ゾーンに置く）

    func upload(_ entry: SongEntry) async {
        guard state == .ready else { return }
        let id = CKRecord.ID(recordName: entry.dayKey, zoneID: zoneID)
        do {
            guard entry.shareSong else {
                _ = try? await privateDB.modifyRecords(saving: [], deleting: [id])
                return
            }
            let record = (try? await privateDB.record(for: id)) ?? CKRecord(recordType: "Post", recordID: id)
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
            _ = try await save(record, in: privateDB)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deletePost(dayKey: String) async {
        guard state == .ready else { return }
        _ = try? await privateDB.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: dayKey, zoneID: zoneID)])
    }

    /// フレンド機能を始めたときに、これまでの記録をまとめて置く
    private func uploadAll() async {
        let entries = (try? AppContainer.shared.mainContext.fetch(FetchDescriptor<SongEntry>())) ?? []
        for entry in entries { await upload(entry) }
    }

    // MARK: - フレンドの追加

    /// フレンドコードから相手の共有リンクを引いて追加する
    func addFriend(code raw: String) async -> Bool {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count == 8 else {
            lastError = S("フレンドコードは8文字です", "Friend codes are 8 characters")
            return false
        }
        guard code != friendCode else {
            lastError = S("自分のコードです", "That's your own code")
            return false
        }
        guard let record = try? await publicDB.record(for: CKRecord.ID(recordName: code)),
              let urlString = record["shareURL"] as? String, let url = URL(string: urlString) else {
            lastError = S("このコードのユーザーが見つかりません", "No user found for this code")
            return false
        }
        return await addFriend(shareURL: url)
    }

    /// 招待リンク・QR コード（共有リンク）から追加する
    func addFriend(shareURL url: URL) async -> Bool {
        do {
            let metadata = try await container.shareMetadata(for: url)
            return await accept(metadata)
        } catch {
            lastError = S("招待リンクを開けませんでした", "Couldn't open the invite link") + "\n" + error.localizedDescription
            return false
        }
    }

    /// 共有を受け入れて、相手にも自分のリンクを送り返す
    func accept(_ metadata: CKShare.Metadata) async -> Bool {
        guard state == .ready else {
            lastError = S("先にニックネームを決めてください", "Set your nickname first")
            return false
        }
        let owner = metadata.ownerIdentity.userRecordID?.recordName ?? metadata.share.recordID.zoneID.ownerName
        if metadata.participantRole == .owner { lastError = S("自分の招待リンクです", "That's your own invite"); return false }
        if blocked.contains(owner) { lastError = S("ブロック中のユーザーです", "You've blocked this user"); return false }
        do {
            _ = try await container.accept(metadata)
            await sendFriendRequest(toZoneOf: metadata.share.recordID.zoneID)
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// 相手のプロフィールからフレンドコードを読み、「自分のリンク」を届ける
    private func sendFriendRequest(toZoneOf zoneID: CKRecordZone.ID) async {
        guard let shareURL,
              let profile = try? await sharedDB.record(for: CKRecord.ID(recordName: Self.profileRecordName, zoneID: zoneID)),
              let theirCode = profile["code"] as? String else { return }
        let request = CKRecord(recordType: "FriendRequest",
                               recordID: CKRecord.ID(recordName: "\(theirCode)-\(friendCode)"))
        request["toCode"] = theirCode
        request["fromCode"] = friendCode
        request["fromNickname"] = nickname
        request["shareURL"] = shareURL.absoluteString
        _ = try? await save(request, in: publicDB)
    }

    /// 自分あての申請を見つけて、相手の共有を受け入れる（相互フレンドにする）
    private func processFriendRequests() async {
        let query = CKQuery(recordType: "FriendRequest", predicate: NSPredicate(format: "toCode == %@", friendCode))
        guard let found = try? await publicDB.records(matching: query, resultsLimit: 100) else { return }
        let alreadyFriends = Set(friends.map(\.ownerName))
        for case let (id, .success(record)) in found.matchResults where !handledRequests.contains(id.recordName) {
            handledRequests.insert(id.recordName)
            guard let urlString = record["shareURL"] as? String, let url = URL(string: urlString),
                  let metadata = try? await container.shareMetadata(for: url) else { continue }
            let owner = metadata.ownerIdentity.userRecordID?.recordName ?? ""
            guard !blocked.contains(owner), !alreadyFriends.contains(metadata.share.recordID.zoneID.ownerName) else { continue }
            _ = try? await container.accept(metadata)
        }
    }

    // MARK: - タイムライン

    func refresh() async {
        guard state == .ready, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await processFriendRequests()

        guard let zones = try? await sharedDB.allRecordZones() else { return }
        var newFriends: [Friend] = []
        var posts: [FriendPost] = []
        for zone in zones where !blocked.contains(zone.zoneID.ownerName) {
            guard let changes = try? await sharedDB.recordZoneChanges(inZoneWith: zone.zoneID, since: nil) else { continue }
            let records = changes.modificationResultsByID.compactMap { try? $0.value.get().record }
            let profile = records.first { $0.recordType == "Profile" }
            let friend = Friend(zoneID: zone.zoneID,
                                nickname: profile?["nickname"] as? String ?? S("フレンド", "Friend"),
                                code: profile?["code"] as? String ?? "")
            newFriends.append(friend)
            posts += records.filter { $0.recordType == "Post" }.map { FriendPost(record: $0, friend: friend) }
        }
        friends = newFriends.sorted { $0.nickname < $1.nickname }
        timeline = posts.sorted { $0.postedAt > $1.postedAt }
    }

    // MARK: - ブロック・通報・フレンド解除

    /// フレンドをやめる：相手の共有から抜け、自分の共有からも相手を外す
    func remove(_ friend: Friend, block: Bool) async {
        if block { blocked.insert(friend.ownerName) }
        _ = try? await sharedDB.modifyRecordZones(saving: [], deleting: [friend.zoneID])
        if let share = try? await zoneShare() {
            for participant in share.participants
            where participant.userIdentity.userRecordID?.recordName == friend.ownerName {
                share.removeParticipant(participant)
            }
            _ = try? await save(share, in: privateDB)
        }
        friends.removeAll { $0.id == friend.id }
        timeline.removeAll { $0.friend.id == friend.id }
    }

    /// 不適切な投稿を開発者に知らせる（公開 DB の Report に残す）。送ったあと相手はブロックする
    func report(_ post: FriendPost, reason: String) async {
        let record = CKRecord(recordType: "Report")
        record["reportedOwner"] = post.friend.ownerName
        record["reportedCode"] = post.friend.code
        record["dayKey"] = post.dayKey
        record["title"] = post.title
        record["memo"] = post.memo
        record["reason"] = reason
        record["reporterCode"] = friendCode
        _ = try? await save(record, in: publicDB)
        await remove(post.friend, block: true)
    }

    // MARK: - CloudKit の小さな手助け

    private func save(_ record: CKRecord, in db: CKDatabase) async throws -> CKRecord {
        let (results, _) = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        guard let result = results[record.recordID] else { return record }
        return try result.get()
    }
}

struct Friend: Identifiable, Hashable {
    let zoneID: CKRecordZone.ID
    let nickname: String
    let code: String
    var id: String { zoneID.ownerName + "/" + zoneID.zoneName }
    var ownerName: String { zoneID.ownerName }
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
        id = friend.id + "/" + record.recordID.recordName
        self.friend = friend
        dayKey = record["dayKey"] as? String ?? record.recordID.recordName
        songID = record["songID"] as? String ?? id
        title = record["title"] as? String ?? ""
        artist = record["artist"] as? String ?? ""
        artworkURL = record["artworkURL"] as? String ?? ""
        previewURL = record["previewURL"] as? String
        appleMusicURL = record["appleMusicURL"] as? String
        memo = record["memo"] as? String ?? ""
        postedAt = record["postedAt"] as? Date ?? record.modificationDate ?? Date()
    }

    var day: Date? { DayKey.date(from: dayKey) }
}
