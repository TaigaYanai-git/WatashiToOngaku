import SwiftUI

/// 誕生日の登録・変更（年齢ごとのプレイリストに使う）
struct BirthdaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Birthday.key) private var stored: Double = 0
    @State private var date: Date

    init() {
        let saved = UserDefaults.standard.double(forKey: Birthday.key)
        _date = State(initialValue: Birthday.date(from: saved)
                      ?? Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(verbatim: S("誕生日を登録すると、「ふりかえり」で年齢ごとのプレイリストを作れます。誕生日はこの iPhone の中だけに保存し、フレンドには見せません。",
                                 "Add your birthday to see playlists for each age in Look Back. It stays on this iPhone and isn't shown to friends."))
                    .font(.caption)
                    .foregroundColor(.dlTextSub)
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .dlCard()
                Button(S("保存", "Save")) {
                    stored = Calendar.current.startOfDay(for: date).timeIntervalSince1970
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                if stored > 0 {
                    Button(S("誕生日を削除", "Remove Birthday"), role: .destructive) {
                        stored = 0
                        dismiss()
                    }
                    .font(.subheadline)
                }
                Spacer()
            }
            .padding(20)
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("誕生日", "Birthday")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(S("キャンセル", "Cancel")) { dismiss() }.foregroundColor(.dlTextSub)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
