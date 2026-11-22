import SwiftUI

/// 読み込み中の印。「今日」の画面と同じレコード盤のアイコンが回る
/// アイコン：Vinyl by Those Icons（Flaticon）。クレジットは設定画面に表記
struct SpinningDisc: View {
    var size: CGFloat = 56
    /// 1回転の秒数
    var period: Double = 1.8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 時刻から角度を出す（状態のアニメーションは表示の切り替えに巻き込まれて止まることがある）
        SwiftUI.TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Image("TodaySongIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(LinearGradient.dlPrimary)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(reduceMotion ? 0 : t.truncatingRemainder(dividingBy: period) / period * 360))
        }
        .accessibilityElement()
        .accessibilityLabel(S("読み込み中", "Loading", "불러오는 중"))
    }
}
