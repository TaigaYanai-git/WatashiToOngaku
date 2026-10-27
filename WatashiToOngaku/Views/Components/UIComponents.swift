import SwiftUI
import UIKit

// MARK: - Design Tokens

extension Color {
    // Backgrounds — UIKit dynamic colours adapt automatically when preferredColorScheme changes
    static let dlBg = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.09, blue: 0.14, alpha: 1)   // #1C1724 dark plum
            : UIColor(red: 0.969, green: 0.957, blue: 0.988, alpha: 1) // #F7F4FC light lavender
    })
    static let dlCard = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.13, blue: 0.22, alpha: 1)   // #26213A
            : UIColor.white
    })
    static let dlCardTint = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.19, green: 0.16, blue: 0.28, alpha: 1)   // #312947
            : UIColor(red: 0.933, green: 0.910, blue: 0.984, alpha: 1) // #EEE8FB
    })
    static let dlDivider = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.24, green: 0.21, blue: 0.32, alpha: 1)
            : UIColor(red: 0.910, green: 0.890, blue: 0.941, alpha: 1) // #E8E3F0
    })

    // Accent — reads from ThemeStore; views that declare @EnvironmentObject ThemeStore
    // re-render automatically when the user picks a new colour in ProfileView.
    static var dlPrimary:    Color { ThemeStore.shared.primary }
    static var dlPrimaryEnd: Color { ThemeStore.shared.primaryEnd }
    static var dlPrimaryBg:  Color { ThemeStore.shared.primaryBg }

    // Secondary accents (fixed)
    static let dlPink = Color(red: 0.976, green: 0.773, blue: 0.816)  // #F9C5D0
    static let dlMint = Color(red: 0.722, green: 0.929, blue: 0.847)  // #B8EDD8

    // Component borders — follow the current theme accent colour
    static var dlDiaryBorder: Color { ThemeStore.shared.primary }
    static var dlVideoBorder:  Color { ThemeStore.shared.primary }

    // Text — dark-adaptive
    static let dlText = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.93, green: 0.90, blue: 0.97, alpha: 1)   // near-white lavender
            : UIColor(red: 0.180, green: 0.145, blue: 0.251, alpha: 1) // #2E2540
    })
    static let dlTextSub = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.60, blue: 0.70, alpha: 1)
            : UIColor(red: 0.557, green: 0.541, blue: 0.600, alpha: 1) // #8E8A99
    })
    static let dlTextLight = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.40, blue: 0.50, alpha: 1)
            : UIColor(red: 0.784, green: 0.769, blue: 0.831, alpha: 1) // #C8C4D4
    })
}

extension LinearGradient {
    // Computed so it picks up accent changes live
    static var dlPrimary: LinearGradient {
        LinearGradient(
            colors: [.dlPrimary, .dlPrimaryEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Button Styles

// ButtonStyle の makeBody はテーマを変えても描き直されないことがあるので、
// テーマを監視する View に包んで、色の変更がすぐ反映されるようにする
private struct ThemedButtonBody<Content: View>: View {
    @ObservedObject private var theme = ThemeStore.shared
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        ThemedButtonBody {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isEnabled
                    ? LinearGradient(colors: [.dlPrimary, .dlPrimaryEnd],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color(.systemGray3), Color(.systemGray3)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .cornerRadius(18)
            .shadow(color: isEnabled ? Color.dlPrimary.opacity(0.28) : .clear,
                    radius: 12, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ThemedButtonBody {
        configuration.label
            .font(.headline)
            .foregroundColor(.dlPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.dlPrimaryBg)
            .cornerRadius(18)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

// MARK: - Text Field Style

struct DarkTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundColor(.dlText)
            .padding(14)
            .background(Color.dlCardTint)
            .cornerRadius(14)
            .tint(.dlPrimary)
    }
}

// MARK: - Loading Overlay

// MARK: - Navigation Bar Background

/// Applies the correct toolbar background: transparent (shows DlBackground pattern) when a
/// background pattern is active, solid dlCard when no pattern is selected.
struct AppNavBarBackground: ViewModifier {
    @ObservedObject private var theme = ThemeStore.shared
    func body(content: Content) -> some View {
        content
            .toolbarBackground(
                theme.bgPatternIndex > 0 ? Color.clear : Color.dlCard,
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func appNavBarBackground() -> some View {
        modifier(AppNavBarBackground())
    }
}

// MARK: - App Background

/// Drop-in replacement for `Color.dlBg` that also renders the selected background pattern.
struct DlBackground: View {
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        ZStack {
            Color.dlBg
            if theme.bgPatternIndex > 0 {
                AppBackgroundPattern(patternIndex: theme.bgPatternIndex, primary: theme.primary)
            }
        }
    }
}

struct AppBackgroundPattern: View {
    let patternIndex: Int
    let primary: Color

    var body: some View {
        Canvas { ctx, size in
            let c = primary.opacity(0.08)
            switch patternIndex {
            case 1:
                // 水玉 — offset every other row
                let spacing: CGFloat = 24
                let r: CGFloat = 2.8
                var row = 0
                var y = spacing * 0.5
                while y < size.height + spacing {
                    let xOff: CGFloat = row % 2 == 0 ? 0 : spacing * 0.5
                    var x = spacing * 0.5 + xOff
                    while x < size.width + spacing {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                        width: r * 2, height: r * 2)),
                                 with: .color(c))
                        x += spacing
                    }
                    y += spacing * 0.866
                    row += 1
                }
            case 2:
                // ボーダー（横）
                let spacing: CGFloat = 22
                var y = spacing
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(path, with: .color(c), lineWidth: 1)
                    y += spacing
                }
            case 3:
                // ボーダー（縦）
                let spacing: CGFloat = 22
                var x = spacing
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(c), lineWidth: 1)
                    x += spacing
                }
            case 4:
                // スター — same offset grid as 水玉
                let spacing: CGFloat = 24
                let outerR: CGFloat = 5.0
                let innerR: CGFloat = outerR * 0.4
                var row = 0
                var y = spacing * 0.5
                while y < size.height + spacing {
                    let xOff: CGFloat = row % 2 == 0 ? 0 : spacing * 0.5
                    var x = spacing * 0.5 + xOff
                    while x < size.width + spacing {
                        ctx.fill(Self.starPath(cx: x, cy: y, outerR: outerR, innerR: innerR),
                                 with: .color(c))
                        x += spacing
                    }
                    y += spacing * 0.866
                    row += 1
                }
            case 5:
                // ハート — same offset grid as 水玉
                let spacing: CGFloat = 26
                let s: CGFloat = 5.0
                var row = 0
                var y = spacing * 0.5
                while y < size.height + spacing {
                    let xOff: CGFloat = row % 2 == 0 ? 0 : spacing * 0.5
                    var x = spacing * 0.5 + xOff
                    while x < size.width + spacing {
                        ctx.fill(Self.heartPath(cx: x, cy: y, s: s), with: .color(c))
                        x += spacing
                    }
                    y += spacing * 0.866
                    row += 1
                }
            default: break
            }
        }
    }

    // 5-pointed star
    private static func starPath(cx: CGFloat, cy: CGFloat, outerR: CGFloat, innerR: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let r = i % 2 == 0 ? outerR : innerR
            let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    // Parametric heart: x=16sin³t, y=-(13cost-5cos2t-2cos3t-cos4t)
    // s controls half-width (total width = 2s); heart is visually centered at (cx, cy)
    private static func heartPath(cx: CGFloat, cy: CGFloat, s: CGFloat) -> Path {
        let scale = s / 16.0
        // Shift so visual center (midpoint of y-extent) sits at cy
        // y-extent: top ≈ -11.5*scale above math origin, bottom ≈ 17*scale below → center at +2.75*scale
        let oy = cy - scale * 2.75
        let steps = 64
        var p = Path()
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let x = cx + 16 * pow(sin(t), 3) * scale
            let y = oy - (13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t)) * scale
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else       { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(.dlPrimary).scaleEffect(1.4)
                Text(message)
                    .foregroundColor(.dlText)
                    .font(.subheadline.weight(.medium))
            }
            .padding(32)
            .background(Color.dlCard)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 8)
        }
    }
}
