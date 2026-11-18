import SwiftData
import SwiftUI

// MARK: - 使い方ツアー
// はじめて開いた人に、記録のしかた・フレンドの作り方・プレイリストの作り方を、
// 画面のボタンを照らしながら順に見せる。設定の「使い方を見る」からもう一度見られる。

/// ツアーで照らす場所。各画面のボタンに `.tourTarget(_:)` で印を付ける
enum TourTarget: Hashable {
    case pickSong, calendarGrid, socialSetup, addFriend
    case timelineOrder, timelineShuffle, timelinePlaylist
    case reviewOrder, reviewShuffle, reviewSave
}

@MainActor
final class AppTour: ObservableObject {
    static let shared = AppTour()
    static let seenKey = "dl_tour_seen_v1"

    @Published private(set) var isActive = false
    @Published var stepIndex = 0
    /// 印を付けた場所の画面上の位置（global 座標）
    @Published private(set) var frames: [TourTarget: CGRect] = [:]

    func setFrame(_ rect: CGRect?, for target: TourTarget) {
        if frames[target] != rect { frames[target] = rect }
    }

    /// まだ見ていない、記録も1件もない人にだけ出す（前から使っている人には出さない）
    func startIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.seenKey) else { return }
        let count = (try? AppContainer.shared.mainContext.fetchCount(FetchDescriptor<SongEntry>())) ?? 0
        guard count == 0 else { defaults.set(true, forKey: Self.seenKey); return }
        start()
    }

    func start() {
        stepIndex = 0
        withAnimation(.easeOut(duration: 0.35)) { isActive = true }
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        withAnimation(.easeIn(duration: 0.25)) { isActive = false }
    }
}

private struct TourTargetModifier: ViewModifier {
    let target: TourTarget
    @State private var lastFrame: CGRect?
    func body(content: Content) -> some View {
        // ナビゲーションバーの項目は、タブを切り替えた直後に動きながら出てくるので、位置が変わるたびに測り直す。
        // 別のタブから戻ったときは位置が変わらず知らせが来ないので、覚えておいた位置を入れ直す
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                lastFrame = rect
                AppTour.shared.setFrame(rect, for: target)
            }
            .onAppear { if let lastFrame { AppTour.shared.setFrame(lastFrame, for: target) } }
            .onDisappear { AppTour.shared.setFrame(nil, for: target) }
    }
}

extension View {
    /// 使い方ツアーで照らす場所として印を付ける
    func tourTarget(_ target: TourTarget) -> some View { modifier(TourTargetModifier(target: target)) }
}

// MARK: - 手順

private struct TourStep {
    enum Chapter { case welcome, record, friends, playlist, start }
    let chapter: Chapter
    let tab: AppTab
    let targets: [TourTarget]
    let title: String
    let message: String

    var chapterLabel: String {
        switch chapter {
        case .welcome, .start: return ""
        case .record: return S("1  記録する", "1  Record", "1  기록하기")
        case .friends: return S("2  フレンドをつくる", "2  Make Friends", "2  친구 만들기")
        case .playlist: return S("3  プレイリストをつくる", "3  Make Playlists", "3  플레이리스트 만들기")
        }
    }

    var chapterIcon: String {
        switch chapter {
        case .welcome, .start, .record: return "square.and.pencil"
        case .friends: return "person.2"
        case .playlist: return "music.note.list"
        }
    }

    @MainActor
    static func all(socialReady: Bool) -> [TourStep] {
        var steps: [TourStep] = [
            TourStep(chapter: .welcome, tab: .today, targets: [],
                     title: S("Our Music へようこそ", "Welcome to Our Music", "Our Music에 오신 것을 환영합니다"),
                     message: S("1日1曲だけ選んで残す、あなたの音楽日記。\n使い方を3つだけ紹介します。",
                                "A music diary where you keep just one song a day.\nHere are the three basics.",
                                "하루에 한 곡만 골라 남기는 음악 일기.\n사용법 세 가지만 소개할게요.")),
            TourStep(chapter: .record, tab: .today, targets: [.pickSong],
                     title: S("今日の1曲を選ぶ", "Pick today's song", "오늘의 한 곡 고르기"),
                     message: S("ここから Apple Music の曲を探して、今日の気分に合う1曲を選びます。ひとことメモも残せます。",
                                "Search Apple Music here and pick the one song that fits your day. You can add a short note too.",
                                "여기서 Apple Music 곡을 찾아 오늘의 기분에 맞는 한 곡을 고릅니다. 짧은 메모도 남길 수 있어요.")),
            TourStep(chapter: .record, tab: .calendar, targets: [.calendarGrid],
                     title: S("カレンダーに並んでいく", "Your calendar fills up", "캘린더가 채워져요"),
                     message: S("選んだ曲はジャケットになって、毎日のマスを埋めていきます。日付を押すとその日の曲が見られます。",
                                "Each song becomes a cover in its day's square. Tap a day to see that song again.",
                                "고른 곡은 앨범 커버가 되어 매일의 칸을 채웁니다. 날짜를 누르면 그날의 곡을 볼 수 있어요.")),
        ]
        if socialReady {
            steps.append(TourStep(chapter: .friends, tab: .timeline, targets: [.addFriend],
                                  title: S("フレンドを招待する", "Invite friends", "친구 초대하기"),
                                  message: S("このボタンから招待リンクを送ったり、コードを入力したりしてフレンドになれます。フレンドの今日の1曲がタイムラインに流れます。",
                                             "Send an invite link or enter a code here. Your friends' songs of the day show up in the timeline.",
                                             "이 버튼에서 초대 링크를 보내거나 코드를 입력해 친구가 될 수 있어요. 친구의 오늘의 한 곡이 타임라인에 올라옵니다.")))
            steps.append(TourStep(chapter: .playlist, tab: .timeline, targets: [.timelineOrder, .timelineShuffle],
                                  title: S("友達との1週間をまとめて聴く", "Play your week with friends", "친구와의 일주일을 한 번에 듣기"),
                                  message: S("あなたとフレンドが選んだ1週間分の曲を、上から順に・シャッフルで Apple Music で再生できます。",
                                             "Play the songs you and your friends picked this week in order or on shuffle in Apple Music.",
                                             "나와 친구들이 고른 일주일 치 곡을 순서대로 또는 셔플로 Apple Music에서 재생할 수 있어요.")))
        } else {
            steps.append(TourStep(chapter: .friends, tab: .timeline, targets: [.socialSetup],
                                  title: S("まずはニックネームを決める", "Start with a nickname", "먼저 닉네임 정하기"),
                                  message: S("ニックネームを決めると、右上のボタンから招待リンクを送ってフレンドを追加できます。フレンドの今日の1曲がタイムラインに流れます。",
                                             "Set a nickname, then send invite links from the top-right button. Your friends' songs of the day show up here.",
                                             "닉네임을 정하면 오른쪽 위 버튼에서 초대 링크를 보내 친구를 추가할 수 있어요. 친구의 오늘의 한 곡이 여기에 올라옵니다.")))
        }
        steps.append(TourStep(chapter: .playlist, tab: .review, targets: [.reviewOrder, .reviewShuffle, .reviewSave],
                              title: S("自分のプレイリストをつくる", "Make your own playlist", "나만의 플레이리스트 만들기"),
                              message: socialReady
                              ? S("ふりかえりでは、1か月・1年分の自分の曲を再生できます。右端のボタンで Apple Music のプレイリストとして保存できます。",
                                  "In Look Back, play your songs from a month or a year. The rightmost button saves them as an Apple Music playlist.",
                                  "돌아보기에서 한 달·일 년 치 내 곡을 재생할 수 있어요. 오른쪽 끝 버튼으로 Apple Music 플레이리스트로 저장할 수 있어요.")
                              : S("ふりかえりでは、1か月・1年分の自分の曲を再生できます。右端のボタンで Apple Music のプレイリストとして保存できます。フレンドができたら、みんなの1週間分もまとめて聴けます。",
                                  "In Look Back, play your songs from a month or a year. The rightmost button saves them as an Apple Music playlist. With friends, you can play their week too.",
                                  "돌아보기에서 한 달·일 년 치 내 곡을 재생할 수 있어요. 오른쪽 끝 버튼으로 Apple Music 플레이리스트로 저장할 수 있어요. 친구가 생기면 모두의 일주일 치도 한 번에 들을 수 있어요.")))
        steps.append(TourStep(chapter: .start, tab: .today, targets: [.pickSong],
                              title: S("さあ、はじめよう", "Let's begin", "자, 시작해요"),
                              message: S("まずは今日の1曲を選んでみましょう。",
                                         "Start by picking today's song.",
                                         "먼저 오늘의 한 곡을 골라 보세요.")))
        return steps
    }
}

// MARK: - 表示

/// アプリ全体の上に重ねる。照らす場所以外を夜の紫で暗くし、テーマカラーの光る枠・指・吹き出しを出す
struct AppTourOverlay: View {
    @ObservedObject private var tour = AppTour.shared
    @ObservedObject private var social = SocialStore.shared
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        if tour.isActive {
            content.transition(.opacity)
        }
    }

    private var steps: [TourStep] { TourStep.all(socialReady: social.state == .ready) }

    private var content: some View {
        let steps = steps
        let index = min(tour.stepIndex, steps.count - 1)
        let step = steps[index]
        return GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let spot = spotlight(for: step, origin: origin)
            ZStack(alignment: .topLeading) {
                // 照らす場所だけ抜いた、夜の紫の幕
                SpotlightShape(rect: spot ?? CGRect(x: geo.size.width / 2, y: geo.size.height / 2, width: 0, height: 0),
                               cornerRadius: spotRadius(spot))
                    .fill(Color(red: 0.08, green: 0.06, blue: 0.12).opacity(0.74), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {}

                if let spot {
                    SpotlightRing(rect: spot, cornerRadius: spotRadius(spot))
                    FloatingNotes(rect: spot)
                    TapPointer(target: spot)
                }

                bubble(step: step, index: index, count: steps.count, isLast: index == steps.count - 1)
                    .frame(width: min(geo.size.width - 40, 440))
                    .position(x: geo.size.width / 2, y: bubbleY(spot: spot, size: geo.size))
                    .id(index)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)), removal: .opacity))
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: spot)
        }
        .ignoresSafeArea()
        .onAppear { go(to: tour.stepIndex) }
        .onChange(of: tour.stepIndex) { _, i in go(to: i) }
    }

    private func go(to i: Int) {
        let steps = steps
        guard steps.indices.contains(i) else { return }
        if steps[i].tab == .today { router.targetDate = Date() }
        router.selectedTab = steps[i].tab
    }

    private func spotlight(for step: TourStep, origin: CGPoint) -> CGRect? {
        let rects = step.targets.compactMap { tour.frames[$0] }.filter { $0.width > 0 && $0.height > 0 }
        guard let first = rects.first else { return nil }
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        return union.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -10, dy: -8)
    }

    private func spotRadius(_ rect: CGRect?) -> CGFloat {
        guard let rect else { return 0 }
        return min(24, min(rect.width, rect.height) / 2)
    }

    /// 照らす場所が上半分なら下に、下半分なら上に吹き出しを置く
    private func bubbleY(spot: CGRect?, size: CGSize) -> CGFloat {
        guard let spot else { return size.height * 0.5 }
        let estimated: CGFloat = 230
        if spot.midY < size.height * 0.5 {
            return min(spot.maxY + 78 + estimated / 2, size.height - estimated / 2 - 40)
        }
        return max(spot.minY - 30 - estimated / 2, estimated / 2 + 60)
    }

    // MARK: 吹き出し

    private func bubble(step: TourStep, index: Int, count: Int, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if step.chapter == .welcome {
                HStack { Spacer(); SpinningRecord(size: 92); Spacer() }
                    .padding(.top, 4)
            } else {
                HStack(spacing: 10) {
                    SpinningRecord(size: 30)
                    if !step.chapterLabel.isEmpty {
                        Label(step.chapterLabel, systemImage: step.chapterIcon)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.dlPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.dlPrimaryBg)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
            }

            VStack(alignment: step.chapter == .welcome ? .center : .leading, spacing: 6) {
                Text(verbatim: step.title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.dlText)
                Text(verbatim: step.message)
                    .font(.subheadline)
                    .foregroundColor(.dlTextSub)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(step.chapter == .welcome ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: step.chapter == .welcome ? .center : .leading)

            HStack(spacing: 12) {
                NoteProgress(index: index, count: count)
                Spacer()
                if !isLast {
                    Button(S("スキップ", "Skip", "건너뛰기")) { tour.finish() }
                        .font(.subheadline)
                        .foregroundColor(.dlTextSub)
                }
                Button {
                    if isLast { tour.finish() } else { tour.stepIndex = index + 1 }
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: isLast ? S("はじめる", "Start", "시작하기")
                                              : index == 0 ? S("見てみる", "Show Me", "보기") : S("次へ", "Next", "다음"))
                        Image(systemName: isLast ? "music.note" : "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(LinearGradient.dlPrimary)
                    .clipShape(Capsule())
                    .shadow(color: Color.dlPrimary.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.dlCard)
                .overlay(alignment: .topTrailing) {
                    // カードの右上に、うっすら五線譜の模様
                    StaffLines().stroke(Color.dlPrimary.opacity(0.10), lineWidth: 1)
                        .frame(width: 120, height: 34)
                        .padding(.top, 16).padding(.trailing, 18)
                        .allowsHitTesting(false)
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(LinearGradient(colors: [.dlPrimary.opacity(0.55), .dlPrimaryEnd.opacity(0.25)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
        )
        .shadow(color: Color.dlPrimary.opacity(0.28), radius: 24, y: 10)
    }
}

// MARK: - 部品

/// 画面全体から角丸の穴を抜いた形。穴の位置はなめらかに動く
private struct SpotlightShape: Shape {
    var rect: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { AnimatablePair(AnimatablePair(rect.origin.x, rect.origin.y),
                             AnimatablePair(AnimatablePair(rect.width, rect.height), cornerRadius)) }
        set {
            rect = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first.first, height: newValue.second.first.second)
            cornerRadius = newValue.second.second
        }
    }

    func path(in bounds: CGRect) -> Path {
        var path = Path(bounds.insetBy(dx: -200, dy: -200))
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        return path
    }
}

/// 照らす場所を囲む、テーマカラーのグラデーションの光る枠（ゆっくり脈打つ）
private struct SpotlightRing: View {
    let rect: CGRect
    let cornerRadius: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius + 6, style: .continuous)
                .stroke(LinearGradient.dlPrimary, lineWidth: 2)
                .frame(width: rect.width + 12, height: rect.height + 12)
                .scaleEffect(pulse ? 1.06 : 1)
                .opacity(pulse ? 0 : 0.7)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(LinearGradient.dlPrimary, lineWidth: 3)
                .frame(width: rect.width, height: rect.height)
                .shadow(color: Color.dlPrimary.opacity(0.9), radius: 10)
        }
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// 枠のまわりをふわふわ漂う音符
private struct FloatingNotes: View {
    let rect: CGRect
    @State private var up = false

    var body: some View {
        ZStack {
            note("music.note", size: 16).position(x: rect.minX - 6, y: rect.minY - 4).offset(y: up ? -6 : 2)
            note("music.quarternote.3", size: 13).position(x: rect.maxX + 4, y: rect.minY + 2).offset(y: up ? 3 : -5)
            note("sparkle", size: 11).position(x: rect.maxX - 10, y: rect.maxY + 8).offset(y: up ? -4 : 2)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { up = true }
        }
    }

    private func note(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(LinearGradient(colors: [.white, .dlPrimaryBg], startPoint: .top, endPoint: .bottom))
            .shadow(color: Color.dlPrimary.opacity(0.8), radius: 6)
    }
}

/// 照らす場所をトントンと指す指。押すたびに波紋が広がる
private struct TapPointer: View {
    let target: CGRect
    @State private var tapping = false

    var body: some View {
        // 指先を照らす場所の中央より少し右下に置く
        let tip = CGPoint(x: target.midX + min(target.width * 0.18, 30), y: target.midY + min(target.height * 0.22, 14))
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(tapping ? 1.5 : 0.4)
                .opacity(tapping ? 0 : 0.9)
                .position(tip)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white)
                .shadow(color: Color.dlPrimary.opacity(0.9), radius: 8)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                // 記号の左上（指先）が tip に来るようにずらす
                .position(x: tip.x + 17, y: tip.y + 20)
                .offset(x: tapping ? 0 : 6, y: tapping ? 0 : 8)
                .scaleEffect(tapping ? 0.92 : 1, anchor: .topLeading)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { tapping = true }
        }
    }
}

/// アプリの「今日の一曲」と同じレコードのアイコンが、ゆっくり回る
private struct SpinningRecord: View {
    let size: CGFloat
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.dlPrimaryBg)
            Image("TodaySongIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(LinearGradient.dlPrimary)
                .padding(size * 0.2)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { angle = 360 }
        }
    }
}

/// いまどこまで進んだかを、音符の列で見せる
private struct NoteProgress: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                if i == index {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LinearGradient.dlPrimary)
                } else {
                    Circle()
                        .fill(i < index ? Color.dlPrimary.opacity(0.55) : Color.dlDivider)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(index + 1) / \(count)"))
    }
}

/// 五線譜の5本線
private struct StaffLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0..<5 {
            let y = rect.minY + rect.height * CGFloat(i) / 4
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}
