// 「私と音楽」のアプリアイコン：グラデーションの背景に、ここで描いたレコードを置く。
// 外部素材は使わず CoreGraphics で描く（Flaticon / SF Symbols はアプリアイコンに使えないため）。
//   swift tools/make_icon.swift <出力appiconset>
import AppKit

let dst = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

struct Palette { let disc: NSColor; let groove: NSColor; let shine: NSColor; let label: NSColor; let hole: NSColor }

func drawRecord(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat, _ p: Palette) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.setFillColor(p.disc.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ctx.restoreGState()
    // 溝
    ctx.setStrokeColor(p.groove.cgColor)
    ctx.setLineWidth(3)
    var gr = r * 0.92
    while gr > r * 0.42 {
        ctx.strokeEllipse(in: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2))
        gr -= r * 0.055
    }
    // 光の反射（左上と右下の弧）
    ctx.setStrokeColor(p.shine.cgColor)
    ctx.setLineCap(.round)
    for (start, end, rr) in [(2.2, 2.9, 0.78), (2.15, 2.6, 0.64), (5.35, 6.05, 0.78), (5.3, 5.75, 0.64)] {
        ctx.setLineWidth(r * 0.05)
        ctx.addArc(center: c, radius: r * rr, startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()
    }
    // ラベルと穴
    let lr = r * 0.32
    ctx.setFillColor(p.label.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - lr, y: c.y - lr, width: lr * 2, height: lr * 2))
    let hr = r * 0.05
    ctx.setFillColor(p.hole.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2))
}

func render(_ name: String, background: (NSColor, NSColor), _ palette: Palette) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // 背景：上が明るい縦のグラデーション（V-Diary のアイコンの雰囲気に合わせる）
    let gradient = CGGradient(colorsSpace: cs, colors: [background.0.cgColor, background.1.cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    drawRecord(ctx, center: CGPoint(x: size / 2, y: size / 2), radius: 340, palette)
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: dst.appendingPathComponent(name))
    print("→ \(name)")
}

render("AppIcon-Default.png", background: (NSColor(white: 0.99, alpha: 1), NSColor(white: 0.88, alpha: 1)),
       Palette(disc: NSColor(white: 0.20, alpha: 1), groove: NSColor(white: 0.14, alpha: 1),
               shine: NSColor(white: 0.45, alpha: 0.9), label: NSColor(white: 0.96, alpha: 1),
               hole: NSColor(white: 0.20, alpha: 1)))
render("AppIcon-Dark.png", background: (NSColor(white: 0.17, alpha: 1), NSColor(white: 0.06, alpha: 1)),
       Palette(disc: NSColor(white: 0.36, alpha: 1), groove: NSColor(white: 0.30, alpha: 1),
               shine: NSColor(white: 0.55, alpha: 0.9), label: NSColor(white: 0.75, alpha: 1),
               hole: NSColor(white: 0.10, alpha: 1)))
render("AppIcon-Tinted.png", background: (NSColor(white: 0.12, alpha: 1), NSColor(white: 0.04, alpha: 1)),
       Palette(disc: NSColor(white: 0.55, alpha: 1), groove: NSColor(white: 0.48, alpha: 1),
               shine: NSColor(white: 0.75, alpha: 0.9), label: NSColor(white: 0.92, alpha: 1),
               hole: NSColor(white: 0.08, alpha: 1)))
