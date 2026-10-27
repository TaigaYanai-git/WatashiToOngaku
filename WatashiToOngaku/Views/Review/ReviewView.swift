import MusicKit
import SwiftData
import SwiftUI

/// 月・年・年齢ごとに、選んだ曲とよく選んだアーティストをふりかえる。右上のボタンで Apple Music で聴ける
struct ReviewView: View {
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var theme: ThemeStore
    @Query(sort: \SongEntry.dayKey, order: .reverse) private var entries: [SongEntry]
    @State private var span: Span = .month
    @State private var anchor = Date()
    @State private var showShare = false
    @ObservedObject private var plus = PlusStore.shared
    /// 再生ボタンで流し始めたら、流れている曲までスクロールして追いかける
    @State private var followsPlayback = false
    @AppStorage(Birthday.key) private var birthdayStored: Double = 0
    /// 表示している年齢（nil なら今の年齢）
    @State private var shownAge: Int?
    @State private var showBirthday = false
    @State private var showPlus = false
    /// Apple Music で流す・保存している最中（"order" / "shuffle" / "save"）
    @State private var working: String?
    @State private var musicError: String?
    @State private var showOffer = false
    @State private var savedName: String?
    @ObservedObject private var musicQueue = SystemMusicPlayer.shared.queue
    @ObservedObject private var musicState = SystemMusicPlayer.shared.state

    enum Span: String, CaseIterable, Identifiable {
        case month, year, age
        var id: String { rawValue }
        var label: String {
            switch self {
            case .month: return S("月", "Month")
            case .year: return S("年", "Year")
            case .age: return S("年齢", "Age")
            }
        }
    }

    private let calendar = Calendar.current

    /// "2026-10" または "2026"
    private var prefix: String {
        let key = DayKey.string(from: anchor)
        return String(key.prefix(span == .month ? 7 : 4))
    }

    private var birthday: Date? { Birthday.date(from: birthdayStored) }
    private var currentAge: Int { birthday.map { Birthday.age(birthday: $0) } ?? 0 }
    private var age: Int { min(shownAge ?? currentAge, currentAge) }

    /// その年齢だった期間の日付（"yyyy-MM-dd"）
    private var ageKeys: (start: String, end: String)? {
        guard let birthday else { return nil }
        let range = Birthday.range(age: age, birthday: birthday)
        return (DayKey.string(from: range.start), DayKey.string(from: range.end))
    }

    private var periodEntries: [SongEntry] {
        if span == .age {
            guard let keys = ageKeys else { return [] }
            return entries.filter { $0.dayKey >= keys.start && $0.dayKey <= keys.end }
        }
        return entries.filter { $0.dayKey.hasPrefix(prefix) }
    }

    private var periodTitle: String {
        switch span {
        case .month: return anchor.formatted(.dateTime.locale(.app).year().month())
        case .year: return anchor.formatted(.dateTime.locale(.app).year())
        case .age: return S("\(age)歳", "Age \(age)", "\(age)세")
        }
    }

    /// ライブラリに保存したプレイリストを、同じ期間なら作り直さずに入れ替えるための名前
    private var playlistKey: String { span == .age ? "age-\(age)" : "mine-\(prefix)" }

    /// 1年ぶん（年・年齢）のプレイリストは Plus
    private var locked: Bool { span != .month && !plus.isPlus }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    Picker("", selection: $span) {
                        ForEach(Span.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if span == .age && birthday == nil {
                        birthdayCard
                    } else {
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
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            // 選んだ曲が流れている（一時停止中も）あいだは、下に操作バーを出す
            .safeAreaInset(edge: .bottom) {
                if let entry = currentEntry, let song = currentSong {
                    NowPlayingBar(artworkURL: entry.artworkURL, title: entry.title,
                                  subtitle: "\(entry.artist) ・ \(entry.day.formatted(.dateTime.locale(.app).month(.defaultDigits).day()))",
                                  isPlaying: song.isPlaying) { followsPlayback = true }
                }
            }
            .onChange(of: currentSong) { _, _ in
                guard followsPlayback, let entry = periodEntries.first(where: isNowPlaying) else { return }
                withAnimation { proxy.scrollTo(entry.dayKey, anchor: .center) }
            }
            }
            .background(DlBackground().ignoresSafeArea())
            // 右上にボタンが3つあって中央に置けないので、タイトルは左上の項目として、端から少し離して置く
            .navigationTitle(Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text(verbatim: S("ふりかえり", "Look Back"))
                        .font(.headline)
                        .foregroundColor(.dlText)
                        .padding(.leading, 10)
                        .fixedSize()
                }
                .sharedBackgroundHiddenIfAvailable()
                // 「選んだ曲」の上から順に／シャッフルで流す・ライブラリに保存する（年・年齢は Plus）
                ToolbarItem(placement: .navigationBarTrailing) {
                    musicButton(id: "order", label: S("上から再生", "Play in Order")) { PlayFromTopIcon() } action: {
                        try await AppleMusicService.play(periodEntries.map(\.songID))
                        followsPlayback = true
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    musicButton(id: "shuffle", label: S("シャッフル再生", "Shuffle")) { Image(systemName: "shuffle") } action: {
                        try await AppleMusicService.play(periodEntries.map(\.songID), shuffle: true)
                        followsPlayback = true
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    musicButton(id: "save", label: S("ライブラリに保存", "Save to Library")) { Image(systemName: "plus.square.on.square") } action: {
                        // ライブラリには日付の古い順に保存する
                        let name = S("Our Music \(periodTitle)", "Our Music \(periodTitle)")
                        try await AppleMusicService.save(periodEntries.sorted { $0.dayKey < $1.dayKey }.map(\.songID), name: name,
                                                         description: S("Our Music で選んだ、\(periodTitle)の今日の一曲",
                                                                        "My songs of the day, \(periodTitle), from Our Music", "Our Music에서 고른 \(periodTitle)의 오늘의 한 곡"),
                                                         key: playlistKey)
                        savedName = name
                    }
                }
            }
            .sheet(isPresented: $showShare) { ShareCardSheet(title: periodTitle, entries: periodEntries) }
            .sheet(isPresented: $showBirthday) { BirthdaySheet() }
            .sheet(isPresented: $showPlus) { PlusView() }
            .alert(Text(verbatim: musicError ?? ""), isPresented: Binding(get: { musicError != nil }, set: { if !$0 { musicError = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .alert(Text(verbatim: S("「\(savedName ?? "")」をライブラリに保存しました", "Saved \"\(savedName ?? "")\" to your library", "'\(savedName ?? "")'을(를) 보관함에 저장했습니다")),
                   isPresented: Binding(get: { savedName != nil }, set: { if !$0 { savedName = nil } })) {
                Button(S("ミュージックで開く", "Open Music")) { AppleMusicService.openMusicApp() }
                Button("OK", role: .cancel) {}
            }
            .musicSubscriptionOffer(isPresented: $showOffer, options: MusicSubscriptionOffer.Options(messageIdentifier: .playMusic))
        }
    }

    private func musicButton<Icon: View>(id: String, label: String, @ViewBuilder icon: () -> Icon,
                                         action: @escaping () async throws -> Void) -> some View {
        Button {
            guard !locked else { showPlus = true; return }
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
            if working == id { ProgressView().tint(.dlPrimary) } else { icon() }
        }
        .foregroundColor(.dlPrimary)
        .disabled(periodEntries.isEmpty || working != nil)
        .accessibilityLabel(label)
    }

    /// 年齢のタブで、誕生日がまだないとき
    private var birthdayCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "gift").font(.largeTitle).foregroundColor(.dlPrimary)
            Text(verbatim: S("誕生日を登録すると、年齢ごとに選んだ曲をふりかえって、プレイリストで聴けます",
                             "Add your birthday to look back on and listen to your songs by age"))
                .font(.subheadline)
                .foregroundColor(.dlTextSub)
                .multilineTextAlignment(.center)
            Button(S("誕生日を登録", "Add Birthday")) { showBirthday = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .dlCard(padding: 24)
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
                .disabled(span == .age && age <= 0)
                .opacity(span == .age && age <= 0 ? 0.35 : 1)
            Spacer()
            VStack(spacing: 2) {
                Text(verbatim: periodTitle).font(.headline).foregroundColor(.dlText)
                // 年齢は、その年齢だった期間も出す（タップで誕生日を変える）
                if span == .age, let birthday {
                    let range = Birthday.range(age: age, birthday: birthday)
                    Button {
                        showBirthday = true
                    } label: {
                        Text(verbatim: "\(range.start.formatted(.dateTime.locale(.app).year().month(.defaultDigits).day())) – \(range.end.formatted(.dateTime.locale(.app).year().month(.defaultDigits).day()))")
                            .font(.caption)
                            .foregroundColor(.dlTextSub)
                    }
                }
            }
            Spacer()
            arrow("chevron.right") { shift(1) }
                .disabled(span == .age && age >= currentAge)
                .opacity(span == .age && age >= currentAge ? 0.35 : 1)
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
        let artists = Set(periodEntries.map(\.artistKey)).count
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
            HStack {
                Label(S("よく選んだアーティスト", "Top Artists"), systemImage: "crown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.dlTextSub)
                Spacer()
                // この期間のよく選んだアーティストのランキングを、シェア画像にする
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.dlPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.dlPrimaryBg)
                        .clipShape(Circle())
                }
                .accessibilityLabel(S("シェア画像を作る", "Create Share Image"))
            }
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
                            Text(entry.day, format: .dateTime.locale(.app).month(.defaultDigits).day())
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
        if span == .age {
            shownAge = max(0, min(age + delta, currentAge))
            return
        }
        if let d = calendar.date(byAdding: span == .month ? .month : .year, value: delta, to: anchor) { anchor = d }
    }
}

private extension ToolbarContent {
    /// iOS 26 の、ツールバーの項目の後ろに付くガラスの丸を付けない（タイトルの文字だけを出す）
    @ToolbarContentBuilder
    func sharedBackgroundHiddenIfAvailable() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
