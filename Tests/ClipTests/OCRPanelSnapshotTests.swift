import AppKit
import XCTest
@testable import Clip

/// Renders the OCR result panel offscreen (window frame included, so the
/// title bar shows) in its recognizing, result and no-text states. Writes
/// PNGs only when `CLIP_SNAPSHOT_DIR` is set; otherwise just checks layout.
/// `CLIP_SNAPSHOT_PREFIX` prefixes the file names (e.g. `before-`).
final class OCRPanelSnapshotTests: XCTestCase {
    private let lines = [
        "Clip turns any region of the screen into text.",
        "Drag across lines in the preview to copy them.",
        "识别结果可以直接编辑后再复制。",
    ]

    func testOCRPanelRendersAllStates() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let image = makeScreenshot()
        let anchor = NSRect(x: 200, y: 300, width: image.size.width, height: image.size.height)

        let recognizing = OCRPanel(image: image, anchorRect: anchor, screen: screen)
        try render(recognizing, name: "recognizing")
        recognizing.dismiss()

        let result = OCRPanel(image: image, anchorRect: anchor, screen: screen)
        result.runOCR(initialResult: OCRResult(lines: recognizedLines(for: image.size)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try render(result, name: "result")
        result.dismiss()

        let empty = OCRPanel(image: image, anchorRect: anchor, screen: screen)
        empty.runOCR(initialResult: OCRResult(text: ""))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        try render(empty, name: "empty")
        empty.dismiss()
    }

    private func render(_ panel: NSPanel, name: String) throws {
        panel.appearance = NSAppearance(named: .aqua)
        let view = try XCTUnwrap(panel.contentView?.superview ?? panel.contentView)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.bounds.height, 150)
        XCTAssertGreaterThanOrEqual(view.bounds.width, 360)

        let env = ProcessInfo.processInfo.environment
        guard let dir = env["CLIP_SNAPSHOT_DIR"] else { return }
        let prefix = env["CLIP_SNAPSHOT_PREFIX"] ?? ""
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)ocr-\(name).png"))
    }

    private func makeScreenshot() -> NSImage {
        let size = NSSize(width: 460, height: 150)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor(white: 0.12, alpha: 1),
            ]
            for (index, line) in self.lines.enumerated() {
                (line as NSString).draw(at: NSPoint(x: 18, y: size.height - 40 - CGFloat(index) * 38),
                                        withAttributes: attrs)
            }
            return true
        }
    }

    private func recognizedLines(for size: NSSize) -> [RecognizedTextLine] {
        lines.enumerated().map { index, text in
            let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15)]).width
            let box = CGRect(x: 18 / size.width,
                             y: (size.height - 40 - CGFloat(index) * 38) / size.height,
                             width: width / size.width,
                             height: 20 / size.height)
            return RecognizedTextLine(text: text, boundingBox: box)
        }
    }
}
