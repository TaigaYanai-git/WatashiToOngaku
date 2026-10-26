import MusicKit
import SwiftData
import SwiftUI

/// 月・年ごとに、選んだ曲とよく選んだアーティストをふりかえる
struct ReviewView: View {
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var theme: ThemeStore
    @Query(sort: \SongEntry.dayKey, order: .reverse) private var entries: [SongEntry]
    @State private var span: Span = .month
    @State private var anchor = Date()
    @State private var showShare = false
    @ObservedObject private var plus = PlusStore.shared
    /// Apple Music で流す・保存している最中（"order" / "shuffle" / "save"）
    @State private var working: String?
    @State private var musicError: String?
    @State private var showOffer = false
    @State private var savedName: String?
    /// 再生ボタンで流し始めたら、流れている曲までスクロールして追いかける
    @State private var followsPlayback = false
    @ObservedObject private var musicQueue = SystemMusicPlayer.shared.queue
    @ObservedObject private var musicState = SystemMusicPlayer.shared.state

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
            ScrollViewReader { proxy in
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
                        playlistCard
                        topArtists
                        songList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            // 選んだ曲が流れている（一時停止中も）あいだは、下に操作バーを出す
            .safeAreaInset(edge: .bottom) {
                if let entry = currentEntry, let song = currentSong {
                    NowPlayingBar(artworkURL: entry.artworkURL, title: entry.title,
                                  subtitle: "\(entry.artist) ・ \(entry.day.formatted(.dateTime.month(.defaultDigits).day()))",
                                  isPlaying: song.isPlaying) { followsPlayback = true }
                }
            }
            .onChange(of: currentSong) { _, _ in
                guard followsPlayback, let entry = periodEntries.first(where: isNowPlaying) else { return }
                withAnimation { proxy.scrollTo(entry.dayKey, anchor: .center) }
            }
            .onChange(of: prefix) { _, _ in savedName = nil }
            }
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: S("ふりかえり", "Look Back")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                        .foregroundColor(.dlPrimary)
                        .disabled(periodEntries.isEmpty)
                        .accessibilityLabel(S("シェア画像を作る", "Create Share Image"))
                }
            }
            .sheet(isPresented: $showShare) { ShareCardSheet(title: periodTitle, entries: periodEntries) }
            .alert(Text(verbatim: musicError ?? ""), isPresented: Binding(get: { musicError != nil }, set: { if !$0 { musicError = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .musicSubscriptionOffer(isPresented: $showOffer, options: MusicSubscriptionOffer.Options(messageIdentifier: .playMusic))
        }
    }

    /// この月・年に選んだ曲を Apple Music で聴く（年は Plus）
    @ViewBuilder
    private var playlistCard: some View {
        if span == .year && !plus.isPlus {
            PlusLockedCard(title: S("1年ぶんの「今日の一曲」を、Apple Music のプレイリストで聴けます",
                                    "Listen to a whole year of your songs as an Apple Music playlist"))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(S("\(periodTitle)のプレイリスト", "\(periodTitle) Playlist"), systemImage: "music.note.list")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.dlTextSub)
                // 「選んだ曲」の上から順に／シャッフルで流す。ライブラリには日付の順に保存する
                HStack(spacing: 10) {
                    musicButton("play.fill", S("上から再生", "Play"), id: "order", primary: true) {
                        try await AppleMusicService.play(periodEntries.map(\.songID))
                        followsPlayback = true
                    }
                    musicButton("shuffle", S("シャッフル", "Shuffle"), id: "shuffle") {
                        try await AppleMusicService.play(periodEntries.map(\.songID), shuffle: true)
                        followsPlayback = true
                    }
                }
                musicButton("plus.square.on.square", S("ライブラリに保存", "Save to Library"), id: "save") {
                    let name = S("Our Music \(periodTitle)", "Our Music \(periodTitle)")
                    try await AppleMusicService.save(periodEntries.sorted { $0.dayKey < $1.dayKey }.map(\.songID), name: name,
                                                     description: S("Our Music で選んだ、\(periodTitle)の今日の一曲",
                                                                    "My songs of the day in \(periodTitle), from Our Music"),
                                                     key: "mine-\(prefix)")
                    savedName = name
                }
                if let savedName {
                    Button {
                        AppleMusicService.openMusicApp()
                    } label: {
                        Label(S("「\(savedName)」を保存しました。ミュージックで開く", "Saved \"\(savedName)\". Open Music"),
                              systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.dlPrimary)
                    }
                }
            }
            .dlCard()
        }
    }

    private func musicButton(_ symbol: String, _ title: String, id: String, primary: Bool = false,
                             action: @escaping () async throws -> Void) -> some View {
        Button {
            working = id
            Task {
                defer { working = nil }
                do {
                    try await action()
                } catch AppleMusicService.Failure.noSubscription(let canSubscribe) where canSubscribe {
                    showOffer = true
                } catch {
                    musicError = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 6) {
                if working == id { ProgressView().tint(primary ? .white : .dlPrimary) } else { Image(systemName: symbol) }
                Text(verbatim: title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(primary ? .white : .dlPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary ? AnyShapeStyle(LinearGradient.dlPrimary) : AnyShapeStyle(Color.dlPrimaryBg))
            .cornerRadius(14)
        }
        .disabled(working != nil)
    }

    /// ミュージックの今の曲（一時停止中も含む）
    private var currentSong: NowPlayingSong? { NowPlayingSong.current(queue: musicQueue, state: musicState) }

    private func matches(_ entry: SongEntry, _ song: NowPlayingSong?) -> Bool {
        song?.matches(songID: entry.songID, title: entry.title, artist: entry.artist) ?? false
    }

    private func isNowPlaying(_ entry: SongEntry) -> Bool {
        guard let song = currentSong, song.isPlaying else { return false }
        return matches(entry, song)
    }

    /// 今の曲が自分の記録にあれば、その記録（表示中の期間を優先）
    private var currentEntry: SongEntry? {
        guard let song = currentSong else { return nil }
        return periodEntries.first { matches($0, song) } ?? entries.first { matches($0, song) }
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
                let playing = isNowPlaying(entry)
                Button {
                    router.targetDate = entry.day
                    router.selectedTab = .today
                } label: {
                    HStack(spacing: 12) {
                        PlayableArtwork(id: entry.songID, artworkURL: entry.artworkURL,
                                        previewURL: entry.previewURL, size: 52, cornerRadius: 8,
                                        songID: entry.songID, clipStart: entry.clipStart)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline.weight(.semibold)).foregroundColor(.dlText).lineLimit(1)
                            Text(entry.artist).font(.caption).foregroundColor(.dlTextSub).lineLimit(1)
                            if !entry.memo.isEmpty {
                                Text(entry.memo).font(.caption).foregroundColor(.dlTextLight).lineLimit(1)
                            }
                        }
                        Spacer()
                        if playing {
                            NowPlayingBadge()
                        } else {
                            Text(entry.day, format: .dateTime.month(.defaultDigits).day())
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.dlTextSub)
                        }
                    }
                    .padding(6)
                    .background(playing ? Color.dlPrimaryBg : Color.clear)
                    .cornerRadius(12)
                    .padding(-6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(entry.dayKey)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dlCard()
    }

    private func shift(_ delta: Int) {
        if let d = calendar.date(byAdding: span == .month ? .month : .year, value: delta, to: anchor) { anchor = d }
    }
}
