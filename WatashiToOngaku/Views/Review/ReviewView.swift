import SwiftData
import SwiftUI

/// 月・年ごとに、選んだ曲とよく選んだアーティストをふりかえる
struct ReviewView: View {
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var theme: ThemeStore
    @Query(sort: \SongEntry.dayKey, order: .reverse) private var entries: [SongEntry]
    @State private var span: Span = .month
    @State private var anchor = Date()

    enum Span: String, CaseIterable, Identifiable {
        case month, year
        var id: String { rawValue }
        var label: String { self == .month ? S("月", "Month") : S("年", "Year") }
    }

    private let calendar = Calendar.current

    /// "2026-10" または "2026"
    private var prefix: String {
        let key = DayKey.string(from: anchor)
        return String(key.prefix(span == .month ? 7 : 4))
    }

    private var periodEntries: [SongEntry] { entries.filter { $0.dayKey.hasPrefix(prefix) } }

    private var periodTitle: String {
        anchor.formatted(span == .month ? .dateTime.year().month() : .dateTime.year())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("", selection: $span) {
                        ForEach(Span.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    periodHeader

                    if periodEntries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note.list").font(.largeTitle).foregroundColor(.dlTextLight)
                            Text(verbatim: S("この期間の記録はまだありません", "No songs in this period yet"))
                                .font(.subheadline).foregroundColor(.dlTextSub)
                        }
                        .frame(maxWidth: .infinity)
                        .dlCard(padding: 32)
                    } else {
                        summary
                        topArtists
                        songList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("ふりかえり", "Look Back")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
        }
    }

    private var periodHeader: some View {
        HStack {
            arrow("chevron.left") { shift(-1) }
            Spacer()
            Text(verbatim: periodTitle).font(.headline).foregroundColor(.dlText)
            Spacer()
            arrow("chevron.right") { shift(1) }
        }
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

    private var summary: some View {
        let artists = Set(periodEntries.map(\.artist)).count
        return HStack(spacing: 0) {
            cell("\(periodEntries.count)", S("曲", "Songs"))
            Rectangle().fill(Color.dlDivider).frame(width: 1, height: 36)
            cell("\(artists)", S("アーティスト", "Artists"))
            Rectangle().fill(Color.dlDivider).frame(width: 1, height: 36)
            cell("\(periodEntries.filter { !$0.memo.isEmpty }.count)", S("メモ", "Notes"))
        }
        .padding(.vertical, 14)
        .background(Color.dlCard)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(.title3.weight(.bold)).foregroundColor(.dlText)
            Text(verbatim: label).font(.caption).foregroundColor(.dlTextSub)
        }
        .frame(maxWidth: .infinity)
    }

    private var topArtists: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(S("よく選んだアーティスト", "Top Artists"), systemImage: "crown")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            ForEach(Array(SongStats.topArtists(periodEntries).enumerated()), id: \.element.id) { rank, item in
                HStack(spacing: 12) {
                    Text("\(rank + 1)")
                        .font(.headline.monospacedDigit())
                        .foregroundColor(rank == 0 ? .dlPrimary : .dlTextSub)
                        .frame(width: 22)
                    ArtworkView(url: item.artworkURL, cornerRadius: 8).frame(width: 40, height: 40)
                    Text(item.artist).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(item.count)\(S("曲", ""))")
                        .font(.subheadline)
                        .foregroundColor(.dlTextSub)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
    }

    private var songList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(S("選んだ曲", "Your Songs"), systemImage: "music.note.list")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            ForEach(periodEntries) { entry in
                Button {
                    router.targetDate = entry.day
                    router.selectedTab = .today
                } label: {
                    HStack(spacing: 12) {
                        PlayableArtwork(id: entry.songID, artworkURL: entry.artworkURL,
                                        previewURL: entry.previewURL, size: 52, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                            Text(entry.artist).font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
                            if !entry.memo.isEmpty {
                                Text(entry.memo).font(.caption).foregroundColor(.dlTextLight).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(entry.day, format: .dateTime.month(.defaultDigits).day())
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.dlTextSub)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
    }

    private func shift(_ delta: Int) {
        if let d = calendar.date(byAdding: span == .month ? .month : .year, value: delta, to: anchor) { anchor = d }
    }
}
