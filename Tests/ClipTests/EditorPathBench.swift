import AppKit
import XCTest
@testable import Clip

/// Main-thread costs between the frozen snapshot and an editable selection:
/// first overlay draw with the snapshot, editor open, and per-frame cost of
/// annotation drags. Shows a window on screen.
/// `CLIP_EDITOR_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter EditorPathBench`
@MainActor
final class EditorPathBench: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["CLIP_EDITOR_BENCH"] != nil }

    private func ms(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    private func summary(_ xs: [Double]) -> String {
        let s = xs.sorted()
        return String(format: "p50=%.2fms p90=%.2fms max=%.2fms n=%d", s[s.count / 2], s[min(s.count - 1, s.count * 9 / 10)], s.last!, s.count)
    }

    private func makeOverlay() throws -> (NSWindow, SelectionView, NSScreen, CGImage) {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = selectionView
        let scale = screen.backingScaleFactor
        let snapshot = ConfirmPathBench.desktopLikeImage(
            width: Int(screen.frame.width * scale), height: Int(screen.frame.height * scale)
        )
        return (window, selectionView, screen, snapshot)
    }

    private func mouse(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// Each capture brings a new CGImage, so time the draw of a fresh image
    /// every iteration (a reused image hits Core Graphics' caches).
    func testOverlaySnapshotFirstDraw() async throws {
        guard enabled else { return }
        let (window, selectionView, screen, _) = try makeOverlay()
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        selectionView.display()
        var applyTimes: [Double] = []
        var redrawTimes: [Double] = []
        var space = "nil"
        for _ in 0..<8 {
            let snapshot = await ConfirmPathBench.sourceImage()
            if let cs = snapshot.colorSpace { space = (cs.name as String?) ?? String(describing: cs) }
            selectionView.awaitsBackgroundSnapshot = true
            selectionView.backgroundSnapshot = nil
            selectionView.display()
            applyTimes.append(ms {
                selectionView.setBackgroundSnapshot(cgImage: snapshot, pointSize: screen.frame.size)
                selectionView.display()
                CATransaction.flush()
            })
            redrawTimes.append(ms {
                selectionView.setNeedsDisplay(selectionView.bounds)
                selectionView.display()
                CATransaction.flush()
            })
        }
        print("EDITORBENCH overlay snapshot first draw (fresh image) \(summary(applyTimes))")
        print("EDITORBENCH overlay full redraw (same image) \(summary(redrawTimes))")
        print("EDITORBENCH snapshot colorspace \(space.prefix(200))")
    }

    func testEditorOpen() throws {
        guard enabled else { return }
        let (window, selectionView, screen, snapshot) = try makeOverlay()
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        selectionView.setBackgroundSnapshot(cgImage: snapshot, pointSize: screen.frame.size)
        selectionView.display()
        if let delay = Double(ProcessInfo.processInfo.environment["CLIP_EDITOR_DELAY"] ?? "") {
            RunLoop.main.run(until: Date().addingTimeInterval(delay))
        }
        let rect = NSRect(x: 300, y: screen.frame.height - 720, width: 900, height: 560)
        var times: [Double] = []
        for _ in 0..<(Int(ProcessInfo.processInfo.environment["CLIP_EDITOR_ITER"] ?? "") ?? 8) {
            selectionView.updateSelectionRect(rect)
            var controller: EditWindowController?
            times.append(ms {
                controller = EditWindowController(
                    captureRect: CGRect(x: 300, y: 160, width: 900, height: 560), screen: screen,
                    selectionRect: rect, selectionViewRect: rect, hostSelectionView: selectionView,
                    preSnapshot: snapshot, isWindowCapture: false, onComplete: { _ in }
                )
                controller?.show()
                window.displayIfNeeded()
                CATransaction.flush()
            })
            controller?.tearDown()
            window.displayIfNeeded()
        }
        print("EDITORBENCH editor open (first=\(String(format: "%.1f", times[0]))ms) \(summary(Array(times.dropFirst())))")
    }

    /// Per-frame cost of dragging an annotation tool over the canvas.
    func testAnnotationDragFrames() throws {
        guard enabled else { return }
        let (window, selectionView, screen, snapshot) = try makeOverlay()
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        selectionView.setBackgroundSnapshot(cgImage: snapshot, pointSize: screen.frame.size)
        selectionView.display()
        let size = NSSize(width: 1200, height: 800)
        let crop = try XCTUnwrap(snapshot.cropping(to: CGRect(x: 200, y: 200, width: size.width * 2, height: size.height * 2)))
        let base = NSImage(cgImage: crop, size: size)

        for (label, windowBase) in [("region", nil as NSImage?), ("window-capture", base)] {
            for tool in [EditTool.rectangle, .mosaic, .arrow] {
                let canvas = EditCanvasView(frame: NSRect(origin: .zero, size: size))
                canvas.windowBaseImage = windowBase
                canvas.preSnapshot = snapshot
                canvas.captureRect = CGRect(x: 100, y: screen.frame.height - 900, width: size.width, height: size.height)
                canvas.captureScreen = screen
                selectionView.addSubview(canvas)
                window.displayIfNeeded()
                // A few committed annotations so redraws are not empty.
                for i in 0..<4 {
                    canvas.activeTool = tool
                    let o = NSPoint(x: 40 + CGFloat(i) * 120, y: 60)
                    canvas.mouseDown(with: mouse(.leftMouseDown, o))
                    canvas.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: o.x + 90, y: o.y + 90)))
                    canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: o.x + 90, y: o.y + 90)))
                }
                canvas.activeTool = tool
                canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 300, y: 300)))
                var frames: [Double] = []
                for step in 1...60 {
                    let p = NSPoint(x: 300 + CGFloat(step) * 8, y: 300 + CGFloat(step) * 6)
                    frames.append(ms {
                        canvas.mouseDragged(with: mouse(.leftMouseDragged, p))
                        canvas.displayIfNeeded(); CATransaction.flush()
                    })
                }
                canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 780, y: 660)))
                // Dragging a committed annotation (move).
                canvas.activeTool = .none
                var moveFrames: [Double] = []
                if canvas.selectAllAnnotations() {
                    canvas.clearAnnotationSelection()
                    canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 85, y: 105)))
                    for step in 1...60 {
                        let p = NSPoint(x: 85 + CGFloat(step) * 4, y: 105 + CGFloat(step) * 3)
                        moveFrames.append(ms {
                            canvas.mouseDragged(with: mouse(.leftMouseDragged, p))
                            canvas.displayIfNeeded(); CATransaction.flush()
                        })
                    }
                    canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 325, y: 285)))
                }
                print("EDITORBENCH \(label) \(tool) draw-drag \(summary(frames))"
                      + (moveFrames.isEmpty ? "" : " | move-drag \(summary(moveFrames))"))
                canvas.removeFromSuperview()
            }
        }
    }
}
