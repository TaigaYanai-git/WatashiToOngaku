import SwiftUI

/// Plus：ダークモードやテーマカラーを変えても変わらないアイコンを選ぶ
struct AppIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fixedTheme: Int?
    @State private var fixedDark: Bool

    init() {
        let ud = UserDefaults.standard
        _fixedTheme = State(initialValue: ud.object(forKey: AppIconManager.fixedThemeKey) != nil ? ud.integer(forKey: AppIconManager.fixedThemeKey) : nil)
        _fixedDark = State(initialValue: ud.bool(forKey: AppIconManager.fixedDarkKey))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button { select(nil, dark: false) } label: {
                        HStack {
                            Text(verbatim: S("固定しない（テーマとダークモードに合わせる）", "Don't fix (follow theme and dark mode)", "고정하지 않음（테마와 다크 모드에 맞춤）"))
                                .font(.subheadline).foregroundColor(.dlText)
                            Spacer()
                            if fixedTheme == nil { Image(systemName: "checkmark").foregroundColor(.dlPrimary) }
                        }
                        .padding(14)
                        .background(Color.dlCard)
                        .cornerRadius(14)
                    }
                    section(S("ライト", "Light", "라이트"), dark: false)
                    section(S("ダーク", "Dark", "다크"), dark: true)
                    Text(verbatim: S("アイコンを変えると iOS のお知らせが出ます。カスタムカラーのアイコンはありません。",
                                     "iOS shows a notice when the icon changes. There's no icon for a custom color.",
                                     "아이콘을 바꾸면 iOS 알림이 표시됩니다. 사용자 지정 색상의 아이콘은 없습니다."))
                        .font(.caption).foregroundColor(.dlTextSub)
                }
                .padding(20)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("アイコンを固定", "Fix App Icon", "아이콘 고정")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("完了", "Done", "완료")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
        }
    }

    private func section(_ title: String, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundColor(.dlTextSub)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(ThemeStore.accents) { accent in
                    let selected = fixedTheme == accent.id && fixedDark == dark
                    Button { select(accent.id, dark: dark) } label: {
                        VStack(spacing: 6) {
                            IconPreview(accent: accent, dark: dark)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.dlPrimary, lineWidth: selected ? 3 : 0)
                                )
                            Text(verbatim: S(accent.name, accent.name))
                                .font(.caption2)
                                .foregroundColor(selected ? .dlPrimary : .dlTextSub)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func select(_ theme: Int?, dark: Bool) {
        fixedTheme = theme
        fixedDark = dark
        AppIconManager.setFixed(theme: theme, isDark: dark)
    }
}

/// アイコンの見本（レコード盤をテーマカラーで描いた簡単なもの）
private struct IconPreview: View {
    let accent: ThemeAccent
    let dark: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(dark ? Color(white: 0.1) : Color.white)
            .frame(width: 64, height: 64)
            .overlay(
                ZStack {
                    Circle().fill(accent.primary).frame(width: 40, height: 40)
                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 1).frame(width: 28, height: 28)
                    Circle().fill(dark ? Color(white: 0.1) : Color.white).frame(width: 8, height: 8)
                }
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
