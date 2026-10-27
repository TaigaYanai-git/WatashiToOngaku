import Foundation

/// フレンドを分けて見るタイムライン（Plus）。「みんな」のほかに、入れるフレンドを選んだタイムラインを作れる。
/// 投稿の取り出し方は変えず、端末内で絞り込むだけなので、iCloud の読み書きは増えない
struct TimelineList: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// 入れるフレンドのコード
    var members: [String] = []
}

@MainActor
final class TimelineListStore: ObservableObject {
    static let shared = TimelineListStore()

    /// 「みんな」のほかに作れるタイムラインの数
    static let maxCustomCount = 5
    /// 「みんな」のタイムライン（選んでいないときもこれ）
    static let allID = "all"

    private static let listsKey = "timeline_lists"
    private static let selectedKey = "timeline_selected"

    /// 自分で作ったタイムライン（「みんな」は含まない）
    @Published private(set) var lists: [TimelineList] = []
    @Published var selectedID: String = TimelineListStore.allID {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.selectedKey) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.listsKey),
           let saved = try? JSONDecoder().decode([TimelineList].self, from: data) {
            lists = saved
        }
        selectedID = UserDefaults.standard.string(forKey: Self.selectedKey) ?? Self.allID
    }

    var canAddMore: Bool { lists.count < Self.maxCustomCount }

    /// 今選んでいるタイムライン。Plus でなくなったら（作ったものは残したまま）「みんな」を見せる
    func current(isPlus: Bool) -> TimelineList? {
        guard isPlus else { return nil }
        return lists.first { $0.id == selectedID }
    }

    /// そのタイムラインに出す投稿か（自分の投稿はどのタイムラインにも出す）
    static func includes(_ post: FriendPost, in list: TimelineList?) -> Bool {
        guard let list else { return true }
        return post.friend.isMe || list.members.contains(post.friend.code)
    }

    func save(_ list: TimelineList) {
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            lists[index] = list
        } else if canAddMore {
            lists.append(list)
        }
        persist()
    }

    func delete(_ list: TimelineList) {
        lists.removeAll { $0.id == list.id }
        if selectedID == list.id { selectedID = Self.allID }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: Self.listsKey)
        }
    }
}
