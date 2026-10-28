// Renders the DMG window background: an arrow from Clip to Applications and a
// one-line note on getting past Gatekeeper the first time. Writes 1x and 2x PNGs;
// make-release.sh merges them into a HiDPI TIFF.
// Usage: swift scripts/dmg-background.swift <out-dir>
import AppKit

let size = NSSize(width: 640, height: 400)
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1).setFill()  // #F5F5F7
    NSRect(origin: .zero, size: size).fill()

    // Icons sit at x 170 and 470, y 180 from the top (see make-release.sh).
    let arrowY = size.height - 180
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 262, y: arrowY))
    arrow.line(to: NSPoint(x: 378, y: arrowY))
    arrow.move(to: NSPoint(x: 364, y: arrowY + 12))
    arrow.line(to: NSPoint(x: 380, y: arrowY))
    arrow.line(to: NSPoint(x: 364, y: arrowY - 12))
    NSColor(srgbRed: 0.525, green: 0.525, blue: 0.545, alpha: 1).setStroke()  // #86868B
    arrow.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let lines = [
        "首次打开被拦截？前往「系统设置 › 隐私与安全性」，点「仍要打开」。",
        "Blocked on first launch? Open System Settings › Privacy & Security and click Open Anyway.",
    ]
    for (index, line) in lines.enumerated() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(srgbRed: 0.431, green: 0.431, blue: 0.451, alpha: 1),  // #6E6E73
            .paragraphStyle: paragraph,
        ]
        NSString(string: line).draw(
            in: NSRect(x: 20, y: 62 - CGFloat(index) * 20, width: size.width - 40, height: 18),
            withAttributes: attributes)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try render(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))
