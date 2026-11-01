import SwiftUI

/// タイムラインの上に出す切り替えのボタン。「＋」で新しいタイムラインを作る（無料で1つ、Plus なら10個まで）
struct TimelineListBar: View {
    @ObservedObject private var store = TimelineListStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @ObservedObject private var social = SocialStore.shared
    @State private var editing: TimelineList?
    @State private var showPlus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(S("みんな", "Everyone", "모두"), count: social.friends.count, id: TimelineListStore.allID)
                    Group {
                        ForEach(store.available(isPlus: plus.isPlus)) { list in
                            chip(list.name, count: members(of: list).count, id: list.id)
                                .contextMenu {
                                    Section(S("メンバー", "Members", "멤버")) {
                                        ForEach(members(of: list)) { Text(verbatim: $0.nickname) }
                                    }
                                    Button(S("編集", "Edit", "편집"), systemImage: "pencil") { editing = list }
                                    Button(S("削除", "Delete", "삭제"), systemImage: "trash", role: .destructive) { store.delete(list) }
                                }
                        }
                    }
                    // 作れる数を超えていたら、Plus でない人には Plus を案内する
                    if !plus.isPlus || store.canAddMore(isPlus: true) {
                        Button {
                            if store.canAddMore(isPlus: plus.isPlus) { editing = TimelineList(name: "") } else { showPlus = true }
                        } label: {
                            Label(S("タイムラインを追加", "Add Timeline", "타임라인 추가"), systemImage: "plus")
                                .labelStyle(.iconOnly)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background(Color.dlCard)
                                .clipShape(Circle())
                        }
                        .foregroundColor(.dlPrimary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            // 選んでいるタイムラインのメンバー（自分で作ったタイムラインはタップで編集）
            if let list = store.current(isPlus: plus.isPlus) {
                memberRow(members(of: list)) { editing = list }
            } else {
                memberRow(social.friends, edit: nil)
            }
        }
        .sheet(item: $editing) { TimelineListEditor(list: $0) }
        .sheet(isPresented: $showPlus) { PlusView() }
    }

    /// タイムラインに入っているフレンド（フレンドをやめた人は数えない）
    private func members(of list: TimelineList) -> [Friend] {
        social.friends.filter { list.members.contains($0.code) }
    }

    private func memberRow(_ members: [Friend], edit: (() -> Void)?) -> some View {
        Button { edit?() } label: {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(members.prefix(5)) { friend in
                        AvatarView(code: friend.code, version: friend.avatarVersion, nickname: friend.nickname, size: 22)
                            .overlay(Circle().stroke(Color.dlCard, lineWidth: 1.5))
                    }
                }
                Text(verbatim: members.isEmpty
                     ? S("メンバーがいません。タップして追加", "No members. Tap to add", "멤버가 없습니다. 탭하여 추가")
                     : members.map(\.nickname).joined(separator: S("、", ", ", ", ")))
                    .font(.caption)
                    .foregroundColor(.dlTextSub)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if edit != nil {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundColor(.dlTextLight)
                }
            }
            .padding(.horizontal, 22)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(edit != nil)
        .accessibilityHint(edit == nil ? "" : S("メンバーを編集", "Edit Members", "멤버 편집"))
    }

    private func chip(_ title: String, count: Int, id: String) -> some View {
        let selected = (store.current(isPlus: plus.isPlus)?.id ?? TimelineListStore.allID) == id
        return Button {
            store.selectedID = id
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                // 人数
                Text(verbatim: "\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(selected ? .white.opacity(0.8) : .dlTextSub)
            }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundColor(selected ? .white : .dlText)
                .background(selected ? Color.dlPrimary : Color.dlCard)
                .clipShape(Capsule())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                    if social.friends.isEmpty {
                        Text(S("フレンドを追加すると、ここで選べます", "Add friends to choose them here", "친구를 추가하면 여기서 고를 수 있습니다"))
                            .foregroundColor(.dlTextSub)
                    }
                    ForEach(social.friends) { friend in
                        Button {
                            if let index = list.members.firstIndex(of: friend.code) {
                                list.members.remove(at: index)
                            } else {
                                list.members.append(friend.code)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(code: friend.code, version: friend.avatarVersion, nickname: friend.nickname, size: 34)
                                Text(verbatim: friend.nickname).foregroundColor(.dlText)
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
