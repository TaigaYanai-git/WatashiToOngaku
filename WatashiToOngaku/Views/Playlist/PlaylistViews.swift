import SwiftUI

/// 「上から再生」のアイコン：下向きの矢印の横に再生マーク
struct PlayFromTopIcon: View {
    var body: some View {
        HStack(spacing: 0) {
            // 矢印は先端を短くしたいので自分で描く。大きさは同じ文字の大きさの SF Symbol に合わせる
            Image(systemName: "arrow.down").fontWeight(.semibold).hidden()
                .overlay { DownArrow() }
                .scaleEffect(0.9)
                .padding(.trailing, -2)
            Image(systemName: "play.fill").scaleEffect(0.85)
        }
    }
}

/// 先端の斜めの線が短い、下向きの矢印
private struct DownArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width * 0.12
        let head = rect.width * 0.32
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + width / 2))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - width / 2))
        path.move(to: CGPoint(x: rect.midX - head, y: rect.maxY - width / 2 - head))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - width / 2))
        path.addLine(to: CGPoint(x: rect.midX + head, y: rect.maxY - width / 2 - head))
        return path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
