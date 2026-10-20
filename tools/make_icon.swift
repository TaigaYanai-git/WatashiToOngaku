// V-Diary のアイコン（猫）に音符を重ねて「私と音楽」のアイコンを作る。
//   swift tools/make_icon.swift <V-Diaryのappiconsetディレクトリ> <出力appiconsetディレクトリ>
import AppKit

let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1]), dst = URL(fileURLWithPath: args[2])

func render(_ name: String, noteColor: NSColor) {
    let base = NSImage(contentsOf: src.appendingPathComponent(name))!
    var rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    let cg = base.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    let hasAlpha = cg.alphaInfo != .none && cg.alphaInfo != .noneSkipLast && cg.alphaInfo != .noneSkipFirst
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (hasAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))

    // 猫の頭の左上あたりに、ふわっと浮かぶ音符を2つ
    let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
    for (symbol, frame, angle) in [("music.note", CGRect(x: 270, y: 660, width: 180, height: 180), 0.18),
                                   ("music.note", CGRect(x: 440, y: 780, width: 125, height: 125), -0.12)] {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
        var r = NSRect(origin: .zero, size: image.size)
        let mask = image.cgImage(forProposedRect: &r, context: nil, hints: nil)!
        ctx.saveGState()
        ctx.translateBy(x: frame.midX, y: frame.midY)
        ctx.rotate(by: angle)
        let aspect = CGFloat(mask.width) / CGFloat(mask.height)
        let h = frame.height, w = h * aspect
        let box = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.clip(to: box, mask: mask)
        ctx.setFillColor(noteColor.cgColor)
        ctx.fill(box)
        ctx.restoreGState()
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: dst.appendingPathComponent(name))
    print("→ \(name)")
}

render("AppIcon-Default.png", noteColor: NSColor(white: 0.18, alpha: 1))
render("AppIcon-Dark.png", noteColor: NSColor(white: 0.85, alpha: 1))
render("AppIcon-Tinted.png", noteColor: NSColor(white: 0.85, alpha: 1))
