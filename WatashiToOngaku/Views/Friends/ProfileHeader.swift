import PhotosUI
import SwiftUI

/// 自分のアイコン（タップで写真を選ぶ）とニックネーム（タップで変更）。設定とフレンド画面で使う
struct ProfileHeader: View {
    @ObservedObject private var social = SocialStore.shared
    var size: CGFloat = 76
    @State private var avatarItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 10) {
            // 開発者は、写真ではなく開発者のアイコン。写真を設定していれば、選び直すか、はずすかを選ぶ
            Group {
                if social.isOfficialOwner {
                    AvatarView(code: social.friendCode, version: social.avatarVersion, nickname: social.nickname, size: size,
                               isDeveloper: true)
                } else if social.avatarVersion > 0 {
                    Menu {
                        Button(S("写真を選ぶ", "Choose Photo", "사진 선택"), systemImage: "photo") { showPicker = true }
                        Button(S("写真をはずす", "Remove Photo", "사진 삭제"), systemImage: "trash", role: .destructive) {
                            Task {
                                working = true
                                if !(await social.removeAvatar()) {
                                    errorMessage = social.lastError ?? S("写真をはずせませんでした", "Couldn't remove the photo", "사진을 삭제하지 못했습니다")
                                }
                                working = false
                            }
                        }
                    } label: { avatar }
                } else {
                    Button { showPicker = true } label: { avatar }
                }
            }
            .disabled(working)
            .photosPicker(isPresented: $showPicker, selection: $avatarItem, matching: .images)
            .accessibilityLabel(S("アイコンを変える", "Change Icon"))
            .onChange(of: avatarItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    avatarItem = nil
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
                    Text(social.nickname).font(.headline).foregroundColor(.dlText).lineLimit(1)
                    Image(systemName: "pencil").font(.caption).foregroundColor(.dlTextSub)
                }
            }
            if !social.isOfficialOwner {
            Text(verbatim: social.avatarVersion > 0
                 ? S("アイコンをタップして、写真を変えたりはずしたりできます", "Tap the icon to change or remove the photo", "아이콘을 탭해 사진을 바꾸거나 삭제할 수 있습니다")
                 : S("アイコンをタップして写真を選べます", "Tap the icon to choose a photo"))
                .font(.caption2)
                .foregroundColor(.dlTextLight)
            }
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

    private var avatar: some View {
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
}
