import SwiftUI

/// プレイリストをライブラリに保存する前に、名前を決める
struct PlaylistNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var focused: Bool
    let songCount: Int
    let onSave: (String) -> Void

    init(defaultName: String, songCount: Int, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: defaultName)
        self.songCount = songCount
        self.onSave = onSave
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: S("プレイリストの名前", "Playlist Name", "플레이리스트 이름"))
                    .font(.subheadline.weight(.semibold)).foregroundColor(.dlTextSub)
                TextField("", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .textFieldStyle(DarkTextFieldStyle())
                Text(verbatim: S("\(songCount)曲をミュージックのライブラリに保存します。同じ期間をもう一度保存すると、前のプレイリストを新しい名前と曲で置き換えます。",
                                 "Saves \(songCount) songs to your Music library. Saving the same period again replaces the earlier playlist.",
                                 "\(songCount)곡을 음악 보관함에 저장합니다. 같은 기간을 다시 저장하면 이전 플레이리스트를 새 이름과 곡으로 바꿉니다."))
                    .font(.caption).foregroundColor(.dlTextSub)
                Spacer()
            }
            .padding(20)
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("ライブラリに保存", "Save to Library", "보관함에 저장")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(S("キャンセル", "Cancel", "취소")) { dismiss() }.foregroundColor(.dlPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("保存", "Save", "저장"), action: save)
                        .foregroundColor(.dlPrimary)
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        dismiss()
        onSave(trimmed)
    }
}
