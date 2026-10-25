import SwiftData
import SwiftUI

/// 自分で選んだ期間に、自分が選んだ曲をまとめるプレイリスト（フレンドの曲は入れない）。
/// 無料は31日まで、Plus は期間の制限なし
struct CustomPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeStore
    @Query(sort: \SongEntry.dayKey) private var entries: [SongEntry]
    @ObservedObject private var plus = PlusStore.shared
    @State private var start = Calendar.current.date(byAdding: .day, value: -13, to: Date())!
    @State private var end = Date()
    @State private var showPlus = false

    private let calendar = Calendar.current

    private var keys: (start: String, end: String) {
        (DayKey.string(from: min(start, end)), DayKey.string(from: max(start, end)))
    }

    /// 選んだ期間の自分の曲（古い順）
    private var periodEntries: [SongEntry] {
        let keys = keys
        return entries.filter { $0.dayKey >= keys.start && $0.dayKey <= keys.end }
    }

    private var days: Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: min(start, end)),
                                 to: calendar.startOfDay(for: max(start, end))).day ?? 0) + 1
    }

    private var title: String {
        let locale = Locale(identifier: theme.language == "en" ? "en_US" : "ja_JP")
        let style = Date.FormatStyle.dateTime.locale(locale).year().month(.defaultDigits).day()
        return "\(min(start, end).formatted(style)) – \(max(start, end).formatted(style))"
    }

    private var locked: Bool { days > PlusStore.freeCustomPlaylistDays && !plus.isPlus }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: S("期間を選ぶと、その間にあなたが選んだ曲をプレイリストにできます",
                                         "Pick a date range to turn the songs you chose into a playlist"))
                            .font(.caption)
                            .foregroundColor(.dlTextSub)
                        DatePicker(S("開始", "From"), selection: $start, in: ...Date(), displayedComponents: .date)
                        DatePicker(S("終了", "To"), selection: $end, in: ...Date(), displayedComponents: .date)
                        Text(verbatim: S("\(days)日間・\(periodEntries.count)曲", "\(days) days · \(periodEntries.count) songs"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundColor(.dlText)
                    .tint(.dlPrimary)
                    .dlCard()

                    if locked {
                        VStack(spacing: 10) {
                            Label(S("\(PlusStore.freeCustomPlaylistDays)日より長い期間は Plus で作れます",
                                    "Ranges over \(PlusStore.freeCustomPlaylistDays) days need Plus"), systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.dlTextSub)
                            Button(S("Plus について見る", "Learn About Plus")) { showPlus = true }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        .dlCard()
                    } else if periodEntries.isEmpty {
                        Text(verbatim: S("この期間に選んだ曲はありません", "No songs in this range"))
                            .font(.subheadline)
                            .foregroundColor(.dlTextSub)
                            .frame(maxWidth: .infinity)
                            .dlCard(padding: 28)
                    } else {
                        PlaylistActions(songIDs: periodEntries.map(\.songID),
                                        name: "Our Music \(title)",
                                        description: S("Our Music で選んだ、\(title)の今日の一曲", "My songs of the day, \(title), from Our Music"),
                                        key: "custom-\(keys.start)-\(keys.end)")
                        VStack(spacing: 12) {
                            ForEach(periodEntries) { entry in
                                HStack(spacing: 12) {
                                    PlayableArtwork(id: entry.songID, artworkURL: entry.artworkURL, previewURL: entry.previewURL,
                                                    size: 48, cornerRadius: 8, songID: entry.songID, clipStart: entry.clipStart)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                                        Text(entry.artist).font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(entry.day, format: .dateTime.month(.defaultDigits).day())
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.dlTextSub)
                                }
                            }
                        }
                        .dlCard()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("カスタムプレイリスト", "Custom Playlist")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(S("閉じる", "Close")) { dismiss() }.foregroundColor(.dlPrimary)
                }
            }
            .sheet(isPresented: $showPlus) { PlusView() }
            .onDisappear { PreviewPlayer.shared.stop() }
        }
    }
}
