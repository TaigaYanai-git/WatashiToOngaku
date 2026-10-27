import SwiftData
import SwiftUI

/// 1日1曲を選んで、ひとことメモを添える
struct TodayView: View {
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var entries: [SongEntry]
    @ObservedObject private var social = SocialStore.shared

    @State private var showPicker = false
    @State private var memoDraft = ""
    @FocusState private var memoFocused: Bool

    private var calendar: Calendar { .current }
    private var day: Date { calendar.startOfDay(for: router.targetDate) }
    private var dayKey: String { DayKey.string(from: day) }
    private var entry: SongEntry? { entries.first { $0.dayKey == dayKey } }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var canGoForward: Bool { day < calendar.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    dateHeader
                    if let entry {
                        songCard(entry)
                        memoCard(entry)
                        if social.state == .ready { shareCard(entry) }
                    } else {
                        emptyCard
                    }
                    streakRow
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DlBackground().ignoresSafeArea())
            .navigationTitle(Text(verbatim: isToday ? S("今日の一曲", "Today's Song") : S("この日の一曲", "Song of the Day")))
            .navigationBarTitleDisplayMode(.inline)
            .appNavBarBackground()
            .toolbar {
                if memoFocused {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(S("完了", "Done")) { saveMemo(); memoFocused = false }
                            .foregroundColor(.dlPrimary)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                MusicPickerSheet(hasSelection: entry != nil, onSelect: select, onClear: clear)
            }
            .onAppear { memoDraft = entry?.memo ?? "" }
            .onChange(of: dayKey) { oldKey, _ in
                saveMemo(forKey: oldKey)
                PreviewPlayer.shared.stop()
                memoDraft = entry?.memo ?? ""
            }
            .onChange(of: memoFocused) { _, focused in if !focused { saveMemo() } }
        }
    }

    // MARK: - 日付

    private var dateHeader: some View {
        HStack {
            circleButton("chevron.left") { shiftDay(-1) }
            Spacer()
            VStack(spacing: 2) {
                Text(verbatim: day.longDayText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.dlText)
                if !isToday {
                    Button(S("今日に戻る", "Back to Today")) { router.targetDate = Date() }
                        .font(.caption)
                        .foregroundColor(.dlPrimary)
                }
            }
            Spacer()
            circleButton("chevron.right") { shiftDay(1) }
                .opacity(canGoForward ? 1 : 0.3)
                .disabled(!canGoForward)
        }
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundColor(.dlPrimary)
                .frame(width: 36, height: 36)
                .background(Color.dlPrimaryBg)
                .clipShape(Circle())
        }
    }

    // MARK: - 曲

    private func songCard(_ entry: SongEntry) -> some View {
        VStack(spacing: 16) {
            PlayableArtwork(id: entry.songID, artworkURL: entry.artworkURL, previewURL: entry.previewURL,
                            size: 250, cornerRadius: 20, songID: entry.songID, clipStart: entry.clipStart)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            VStack(spacing: 4) {
                Text(entry.title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.dlText)
                    .multilineTextAlignment(.center)
                Text(entry.artist)
                    .font(.subheadline)
                    .foregroundColor(.dlTextSub)
                if !entry.albumTitle.isEmpty {
                    Text(entry.albumTitle)
                        .font(.caption)
                        .foregroundColor(.dlTextLight)
                }
            }
            HStack(spacing: 10) {
                if let link = entry.appleMusicURL.flatMap(URL.init(string:)) {
                    Button {
                        openURL(link)
                    } label: {
                        Label(S("Apple Musicで聴く", "Open in Apple Music"), systemImage: "music.note")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button { showPicker = true } label: {
                        Label(S("曲を変える", "Change Song"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                // 曲を変えるのはたまにしか使わないので、アイコンだけの小さいボタンにする
                if entry.appleMusicURL != nil {
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundColor(.dlPrimary)
                        .frame(width: 52, height: 52)
                        .background(Color.dlPrimaryBg)
                        .cornerRadius(18)
                }
                .accessibilityLabel(S("曲を変える", "Change Song"))
                }
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .dlCard(padding: 20)
    }

    private func memoCard(_ entry: SongEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(S("ひとことメモ", "A Short Note"), systemImage: "pencil.line")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dlTextSub)
            TextField(S("この曲を選んだ理由や、今日のできごと", "Why this song? What happened today?"),
                      text: $memoDraft, axis: .vertical)
                .lineLimit(3...8)
                .focused($memoFocused)
                .textFieldStyle(DarkTextFieldStyle())
        }
        .dlCard()
    }

    /// この日の曲をフレンドに見せるか（日ごとに選べる）
    private func shareCard(_ entry: SongEntry) -> some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(get: { entry.shareSong }, set: { entry.shareSong = $0; changed(entry) })) {
                Label(S("フレンドに共有", "Share with Friends"), systemImage: "person.2")
            }
            if entry.shareSong {
                Divider()
                Toggle(isOn: Binding(get: { entry.shareMemo }, set: { entry.shareMemo = $0; changed(entry) })) {
                    Label(S("メモも見せる", "Include Note"), systemImage: "text.bubble")
                }
            }
        }
        .font(.subheadline)
        .foregroundColor(.dlText)
        .tint(.dlPrimary)
        .dlCard()
    }

    private var emptyCard: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.dlPrimaryBg)
                    .frame(width: 200, height: 200)
                // アイコン：Vinyl by Those Icons（Flaticon）。クレジットは設定画面に表記
                Image("TodaySongIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(LinearGradient.dlPrimary)
                    .frame(width: 110, height: 110)
                    .accessibilityHidden(true)
            }
            Text(verbatim: isToday ? S("今日の一曲はまだ選ばれていません", "No song for today yet")
                                   : S("この日の曲は記録されていません", "No song recorded for this day"))
                .font(.subheadline)
                .foregroundColor(.dlTextSub)
            Button {
                showPicker = true
            } label: {
                Label(isToday ? S("今日の一曲を選ぶ", "Pick Today's Song") : S("この日の曲を選ぶ", "Pick a Song"),
                      systemImage: "magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .dlCard(padding: 24)
    }

    private var streakRow: some View {
        HStack(spacing: 0) {
            stat("\(SongStats.currentStreak(entries))\(S("日", " days"))", S("連続記録", "Streak"))
            Rectangle().fill(Color.dlDivider).frame(width: 1, height: 36)
            stat("\(entries.count)\(S("曲", " songs"))", S("これまでの曲", "All Songs"))
        }
        .padding(.vertical, 14)
        .background(Color.dlCard)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(.title3.weight(.bold)).foregroundColor(.dlText)
            Text(verbatim: label).font(.caption).foregroundColor(.dlTextSub)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 操作

    private func shiftDay(_ delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: delta, to: day),
              next <= calendar.startOfDay(for: Date()) else { return }
        router.targetDate = next
    }

    private func select(_ song: PickedSong) {
        if let entry {
            entry.apply(song)
        } else {
            let new = SongEntry(dayKey: dayKey, song: song)
            new.memo = memoDraft
            context.insert(new)
        }
        try? context.save()
        if let saved = entries.first(where: { $0.dayKey == dayKey }) ?? (try? context.fetch(FetchDescriptor<SongEntry>()))?.first(where: { $0.dayKey == dayKey }) {
            changed(saved)
        }
        Task { await AppleMusicService.fillArtistIDs(in: context) }
    }

    /// 保存して、フレンド機能を使っていれば共有している投稿も更新する
    private func changed(_ entry: SongEntry) {
        entry.updatedAt = Date()
        try? context.save()
        Task { await social.upload(entry) }
    }

    private func clear() {
        let key = dayKey
        Task { await social.deletePost(dayKey: key) }
        if let entry { context.delete(entry) }
        memoDraft = ""
        try? context.save()
    }

    /// 入力中のメモを保存する。日付を切り替えたときは、切り替える前の日（key）に保存する
    private func saveMemo(forKey key: String? = nil) {
        let key = key ?? dayKey
        guard let target = entries.first(where: { $0.dayKey == key }) else { return }
        if target.memo != memoDraft {
            target.memo = memoDraft
            changed(target)
        }
    }
}
