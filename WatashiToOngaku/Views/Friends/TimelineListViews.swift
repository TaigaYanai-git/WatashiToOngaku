import SwiftUI

/// タイムラインの上の切り替えタブ。下線はタイムラインを横にめくる指に合わせて動く。
/// 作成・編集・削除は右端のボタンにまとめる（無料で10個、Plus なら100個まで）
struct TimelineGroupTabs: View {
    /// 横にめくっている途中の位置（0 =「みんな」、1 = 1つ目のタイムライン…）
    let progress: CGFloat
    @ObservedObject private var store = TimelineListStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @State private var editing: TimelineList?
    @State private var deleting: TimelineList?
    @State private var showPlus = false
    @State private var frames: [String: CGRect] = [:]

    /// タブの文字の左右の余白。下線は文字の幅に合わせる
    private static let inset: CGFloat = 10

    private var tabs: [(id: String, name: String, list: TimelineList?)] {
        [(TimelineListStore.allID, S("みんな", "Everyone", "모두"), nil)]
            + store.available(isPlus: plus.isPlus).map { ($0.id, $0.name, $0) }
    }

    private var current: TimelineList? { store.current(isPlus: plus.isPlus) }
    private var currentID: String { current?.id ?? TimelineListStore.allID }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            tabButton(tab.name, id: tab.id, list: tab.list,
                                      selected: index == Int(progress.rounded()))
                        }
                    }
                    .padding(.horizontal, 10)
                    .coordinateSpace(name: "timelineTabs")
                    .overlay(alignment: .bottomLeading) { indicator }
                }
                .onChange(of: currentID) { _, id in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(currentID, anchor: .center) }
            }
            manageMenu
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.dlDivider).frame(height: 1) }
        .sheet(item: $editing) { TimelineListEditor(list: $0) }
        .sheet(isPresented: $showPlus) { PlusView() }
        .confirmationDialog(Text(verbatim: S("「\(deleting?.name ?? "")」を削除しますか？", "Delete \"\(deleting?.name ?? "")\"?", "「\(deleting?.name ?? "")」을(를) 삭제할까요?")),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { list in
            Button(S("削除", "Delete", "삭제"), role: .destructive) { store.delete(list) }
        } message: { _ in
            Text(verbatim: S("フレンドや投稿は消えません", "Your friends and posts stay.", "친구와 게시물은 사라지지 않습니다"))
        }
    }

    private func tabButton(_ name: String, id: String, list: TimelineList?, selected: Bool) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) { store.selectedID = id }
        } label: {
            Text(verbatim: name)
                .font(.subheadline.weight(selected ? .bold : .medium))
                .foregroundColor(selected ? .dlText : .dlTextSub)
                .lineLimit(1)
                .padding(.horizontal, Self.inset)
                .padding(.top, 8)
                .padding(.bottom, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(id)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("timelineTabs")) } action: { frames[id] = $0 }
        .contextMenu {
            if let list {
                Button(S("編集", "Edit", "편집"), systemImage: "pencil") { editing = list }
                Button(S("削除", "Delete", "삭제"), systemImage: "trash", role: .destructive) { deleting = list }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 選んでいるタブの下線。めくっている途中は、隣のタブとのあいだを幅ごとなめらかにつなぐ
    @ViewBuilder
    private var indicator: some View {
        let ids = tabs.map(\.id)
        let p = min(max(progress, 0), CGFloat(max(ids.count - 1, 0)))
        let i = Int(p.rounded(.down))
        let f = p - CGFloat(i)
        if let a = frames[ids[i]] {
            let b = frames[ids[min(i + 1, ids.count - 1)]] ?? a
            let x = a.minX + (b.minX - a.minX) * f + Self.inset
            let w = (a.width + (b.width - a.width) * f) - Self.inset * 2
            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                .fill(Color.dlPrimary)
                .frame(width: max(w, 8), height: 3)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }

    /// 作成・編集・削除をまとめたボタン
    private var manageMenu: some View {
        Menu {
            // 作れる数を超えていたら、Plus でない人には Plus を案内する
            if !plus.isPlus || store.canAddMore(isPlus: true) {
                Button(S("新しいタイムライン", "New Timeline", "새 타임라인"), systemImage: "plus") {
                    if store.canAddMore(isPlus: plus.isPlus) { editing = TimelineList(name: "") } else { showPlus = true }
                }
            }
            if let current {
                Section(current.name) {
                    Button(S("メンバーと名前を編集", "Edit Name & Members", "이름과 멤버 편집"), systemImage: "pencil") { editing = current }
                    Button(S("削除", "Delete", "삭제"), systemImage: "trash", role: .destructive) { deleting = current }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlPrimary)
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(S("タイムラインを管理", "Manage Timelines", "타임라인 관리"))
    }
}

/// タイムラインのいちばん上に出す、そのタイムラインのメンバー（自分で作ったものはタップで編集）
struct TimelineMembersRow: View {
    /// nil なら「みんな」
    let list: TimelineList?
    @ObservedObject private var social = SocialStore.shared
    @State private var editing: TimelineList?

    private var members: [Friend] {
        guard let list else { return social.allFriends }
        // フレンドをやめた人は数えない
        return social.allFriends.filter { list.members.contains($0.code) }
    }

    var body: some View {
        let members = members
        Button { editing = list } label: {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(members.prefix(5)) { friend in
                        AvatarView(friend: friend, size: 22)
                            .overlay(Circle().stroke(Color.dlCard, lineWidth: 1.5))
                    }
                }
                Text(verbatim: members.isEmpty
                     ? S("メンバーがいません。タップして追加", "No members. Tap to add", "멤버가 없습니다. 탭하여 추가")
                     : list == nil
                     ? S("フレンド全員（\(members.count)人）", "All friends (\(members.count))", "친구 전체 (\(members.count)명)")
                     : members.map(\.nickname).joined(separator: S("、", ", ", ", ")))
                    .font(.caption)
                    .foregroundColor(.dlTextSub)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if list != nil {
                    Text(verbatim: S("編集", "Edit", "편집"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.dlPrimary)
                }
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(list != nil)
        .accessibilityHint(list == nil ? "" : S("メンバーを編集", "Edit Members", "멤버 편집"))
        .sheet(item: $editing) { TimelineListEditor(list: $0) }
    }
}

/// タイムラインの名前と、入れるフレンドを選ぶ
struct TimelineListEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var social = SocialStore.shared
    @State private var list: TimelineList
    private let isNew: Bool

    init(list: TimelineList) {
        _list = State(initialValue: list)
        isNew = !TimelineListStore.shared.lists.contains { $0.id == list.id }
    }

    private var trimmedName: String { list.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(S("名前（例：大学の友達）", "Name (e.g. College friends)", "이름（예: 대학 친구）"), text: $list.name)
                }
                Section {
                    if social.allFriends.isEmpty {
                        Text(S("フレンドを追加すると、ここで選べます", "Add friends to choose them here", "친구를 추가하면 여기서 고를 수 있습니다"))
                            .foregroundColor(.dlTextSub)
                    }
                    ForEach(social.allFriends) { friend in
                        Button {
                            if let index = list.members.firstIndex(of: friend.code) {
                                list.members.remove(at: index)
                            } else {
                                list.members.append(friend.code)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(friend: friend, size: 34)
                                Text(verbatim: friend.nickname).foregroundColor(.dlText).lineLimit(1)
                                Spacer()
                                Image(systemName: list.members.contains(friend.code) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(list.members.contains(friend.code) ? .dlPrimary : .dlTextLight)
                            }
                        }
                    }
                } header: {
                    Text(S("入れるフレンド", "Friends in this timeline", "이 타임라인에 넣을 친구"))
                } footer: {
                    Text(S("あなたの投稿は、どのタイムラインにも出ます", "Your own posts appear in every timeline", "내 게시물은 모든 타임라인에 표시됩니다"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: isNew ? S("新しいタイムライン", "New Timeline", "새 타임라인") : S("タイムラインを編集", "Edit Timeline", "타임라인 편집")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(S("キャンセル", "Cancel", "취소")) { dismiss() }.foregroundColor(.dlPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("保存", "Save", "저장")) {
                        list.name = trimmedName
                        TimelineListStore.shared.save(list, isPlus: PlusStore.shared.isPlus)
                        TimelineListStore.shared.selectedID = list.id
                        dismiss()
                    }
                    .foregroundColor(.dlPrimary)
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}
