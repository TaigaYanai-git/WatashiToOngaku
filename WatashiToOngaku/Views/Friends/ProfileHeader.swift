import PhotosUI
import SwiftUI

/// 自分のアイコン（タップで写真を選ぶ）とニックネーム（タップで変更）。設定とフレンド画面で使う
struct ProfileHeader: View {
    @ObservedObject private var social = SocialStore.shared
    var size: CGFloat = 76
    @State private var avatarItem: PhotosPickerItem?
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $avatarItem, matching: .images) {
                AvatarView(code: social.friendCode, version: social.avatarVersion, nickname: social.nickname, size: size)
                    .overlay {
                        if working { ProgressView().tint(.white) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: size * 0.32))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.dlPrimary)
                    }
            }
            .accessibilityLabel(S("アイコンを変える", "Change Icon"))
            .onChange(of: avatarItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    working = true
                    if !(await social.setAvatar(data)) {
                        errorMessage = social.lastError ?? S("アイコンを変えられませんでした", "Couldn't change icon")
                    }
                    working = false
                }
            }
            Button {
                nameDraft = social.nickname
                editingName = true
            } label: {
                HStack(spacing: 4) {
                    Text(social.nickname).font(.headline).foregroundColor(.dlText)
                    Image(systemName: "pencil").font(.caption).foregroundColor(.dlTextSub)
                }
            }
            Text(verbatim: S("アイコンをタップして写真を選べます", "Tap the icon to choose a photo"))
                .font(.caption2)
                .foregroundColor(.dlTextLight)
        }
        .alert(Text(verbatim: S("ニックネーム", "Nickname")), isPresented: $editingName) {
            TextField("", text: $nameDraft)
            Button(S("保存", "Save")) { Task { await social.rename(nameDraft) } }
            Button(S("キャンセル", "Cancel"), role: .cancel) {}
        }
        .alert(Text(verbatim: errorMessage ?? ""), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        }
    }
}
