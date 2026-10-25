import SwiftData
import SwiftUI

/// 月のカレンダーに、毎日の曲のジャケットを並べる
struct SongCalendarView: View {
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var theme: ThemeStore
    @Query private var entries: [SongEntry]
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var showCustomPlaylist = false

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var byKey: [String: SongEntry] {
        Dictionary(entries.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    monthHeader
                    weekdayHeader
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                            if let day {
                                DayCell(day: day, entry: byKey[DayKey.string(from: day)]) {
                                    router.targetDate = day
                                    router.selectedTab = .today
                                }
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                    monthSummary
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("カレンダー", "Calendar")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(S("カスタムプレイリストを作る", "Create Custom Playlist"), systemImage: "music.note.list") {
                            showCustomPlaylist = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .foregroundColor(.dlPrimary)
                    .accessibilityLabel(S("メニュー", "Menu"))
                }
            }
            .sheet(isPresented: $showCustomPlaylist) { CustomPlaylistView() }
        }
    }

    private var monthHeader: some View {
        HStack {
            arrow("chevron.left") { shiftMonth(-1) }
            Spacer()
            Text(month, format: .dateTime.year().month())
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlText)
            Spacer()
            arrow("chevron.right") { shiftMonth(1) }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundColor(.dlPrimary)
                .frame(width: 36, height: 36)
                .background(Color.dlPrimaryBg)
                .clipShape(Circle())
        }
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(S("日,月,火,水,木,金,土", "Sun,Mon,Tue,Wed,Thu,Fri,Sat").components(separatedBy: ","), id: \.self) {
                Text($0)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.dlTextLight)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthSummary: some View {
        let monthEntries = entries.filter { $0.dayKey.hasPrefix(String(DayKey.string(from: month).prefix(7))) }
        return HStack(spacing: 0) {
            summaryCell("\(monthEntries.count)\(S("曲", " songs"))", S("この月の記録", "This Month"))
            Rectangle().fill(Color.dlDivider).frame(width: 1, height: 36)
            summaryCell("\(SongStats.currentStreak(entries))\(S("日", " days"))", S("現在の連続", "Current Streak"))
            Rectangle().fill(Color.dlDivider).frame(width: 1, height: 36)
            summaryCell("\(SongStats.bestStreak(entries))\(S("日", " days"))", S("最長記録", "Best"))
        }
        .padding(.vertical, 14)
        .background(Color.dlCard)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.top, 6)
    }

    private func summaryCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(.headline).foregroundColor(.dlText)
            Text(verbatim: label).font(.caption).foregroundColor(.dlTextSub)
        }
        .frame(maxWidth: .infinity)
    }

    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = calendar.component(.weekday, from: month) - 1
        return Array(repeating: nil, count: leading)
            + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func shiftMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: month) { month = d }
    }
}

private struct DayCell: View {
    let day: Date
    let entry: SongEntry?
    let onTap: () -> Void

    private var isFuture: Bool { day > Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let entry {
                        ArtworkView(url: entry.artworkURL, cornerRadius: 0)
                    } else {
                        Color.dlCard
                    }
                }
                .clipped()
                .overlay(alignment: .topLeading) {
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(entry != nil ? .white : .dlTextSub)
                        .shadow(color: entry != nil ? .black.opacity(0.9) : .clear, radius: 0.5, y: 1)
                        .shadow(color: entry != nil ? .black.opacity(0.6) : .clear, radius: 3)
                        .padding(4)
                }
                .overlay {
                    if Calendar.current.isDateInToday(day) {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color.dlPrimary, lineWidth: 2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(entry != nil ? 0.06 : 0.03), radius: 6, y: 2)
                .opacity(isFuture ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(entry.map { "\(day.longDayText) \($0.title) \($0.artist)" } ?? day.longDayText)
    }
}
