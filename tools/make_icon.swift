// 「私と音楽」のアプリアイコン：V-Diary の猫の後ろに、ここで描いたレコードを置く。
// レコードは外部素材を使わず CoreGraphics で描く（Flaticon / SF Symbols はアプリアイコンに使えないため）。
//   swift tools/make_icon.swift <V-Diaryのappiconset> <出力appiconset>
import AppKit

let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1]), dst = URL(fileURLWithPath: args[2])
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func cgImage(_ name: String) -> CGImage {
    var r = NSRect(x: 0, y: 0, width: size, height: size)
    return NSImage(contentsOf: src.appendingPathComponent(name))!.cgImage(forProposedRect: &r, context: nil, hints: nil)!
}

/// 通常版のアイコンから、猫の部分（背景より暗い画素）だけのマスクを作る
func catMask() -> CGImage {
    var px = [UInt8](repeating: 0, count: size * size * 4)
    let ctx = CGContext(data: &px, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cgImage("AppIcon-Default.png"), in: CGRect(x: 0, y: 0, width: size, height: size))
    var mask = [UInt8](repeating: 0, count: size * size)
    for i in 0..<(size * size) {
        let l = (Int(px[i * 4]) + Int(px[i * 4 + 1]) + Int(px[i * 4 + 2])) / 3
        // 猫の縁をなめらかにするため、しきい値付近は半透明にする
        mask[i] = UInt8(max(0, min(255, (150 - l) * 6)))
    }
    return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: CGDataProvider(data: Data(mask) as CFData)!,
                   decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

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

func render(_ name: String, _ palette: Palette, mask: CGImage) {
    let base = cgImage(name)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.draw(base, in: full)
    // 猫の左後ろにレコード
    drawRecord(ctx, center: CGPoint(x: 400, y: 470), radius: 270, palette)
    // 猫を上に描き戻す
    ctx.saveGState()
    ctx.clip(to: full, mask: mask)
    ctx.draw(base, in: full)
    ctx.restoreGState()
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: dst.appendingPathComponent(name))
    print("→ \(name)")
}

let mask = catMask()
render("AppIcon-Default.png", Palette(disc: NSColor(white: 0.62, alpha: 1), groove: NSColor(white: 0.56, alpha: 1),
                                      shine: NSColor(white: 0.80, alpha: 0.8), label: NSColor(white: 0.95, alpha: 1),
                                      hole: NSColor(white: 0.62, alpha: 1)), mask: mask)
render("AppIcon-Dark.png", Palette(disc: NSColor(white: 0.30, alpha: 1), groove: NSColor(white: 0.25, alpha: 1),
                                   shine: NSColor(white: 0.45, alpha: 0.8), label: NSColor(white: 0.62, alpha: 1),
                                   hole: NSColor(white: 0.12, alpha: 1)), mask: mask)
render("AppIcon-Tinted.png", Palette(disc: NSColor(white: 0.40, alpha: 1), groove: NSColor(white: 0.34, alpha: 1),
                                     shine: NSColor(white: 0.60, alpha: 0.8), label: NSColor(white: 0.85, alpha: 1),
                                     hole: NSColor(white: 0.15, alpha: 1)), mask: mask)
