import SwiftUI

/// タイムラインの上に出す切り替えのボタン。「＋」で新しいタイムラインを作る（Plus）
struct TimelineListBar: View {
    @ObservedObject private var store = TimelineListStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @State private var editing: TimelineList?
    @State private var showPlus = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(S("みんな", "Everyone", "모두"), id: TimelineListStore.allID)
                if plus.isPlus {
                    ForEach(store.lists) { list in
                        chip(list.name, id: list.id)
                            .contextMenu {
                                Button(S("編集", "Edit", "편집"), systemImage: "pencil") { editing = list }
                                Button(S("削除", "Delete", "삭제"), systemImage: "trash", role: .destructive) { store.delete(list) }
                            }
                    }
                }
                if !plus.isPlus || store.canAddMore {
                    Button {
                        if plus.isPlus { editing = TimelineList(name: "") } else { showPlus = true }
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
        .sheet(item: $editing) { TimelineListEditor(list: $0) }
        .sheet(isPresented: $showPlus) { PlusView() }
    }

    private func chip(_ title: String, id: String) -> some View {
        let selected = (store.current(isPlus: plus.isPlus)?.id ?? TimelineListStore.allID) == id
        return Button {
            store.selectedID = id
        } label: {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
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
                        TimelineListStore.shared.save(list)
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
