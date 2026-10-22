import AppKit
import XCTest
@testable import capcap

@MainActor
final class FixedImageCropGeometryTests: XCTestCase {
    func testInsetViewportMapsToMatchingSourceRect() {
        let sourceRect = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let oldViewport = NSRect(x: 10, y: 20, width: 100, height: 80)
        let newViewport = NSRect(x: 35, y: 20, width: 75, height: 60)

        let result = FixedImageCropGeometry.adjustedSourceRect(
            sourceRect,
            from: oldViewport,
            to: newViewport,
            imageBounds: sourceRect
        )

        XCTAssertEqual(result, NSRect(x: 250, y: 0, width: 750, height: 600))
    }

    func testMovingCroppedViewportPansWithinOriginalImage() {
        let result = FixedImageCropGeometry.adjustedSourceRect(
            NSRect(x: 100, y: 100, width: 600, height: 400),
            from: NSRect(x: 0, y: 0, width: 60, height: 40),
            to: NSRect(x: 10, y: 5, width: 60, height: 40),
            imageBounds: NSRect(x: 0, y: 0, width: 1000, height: 800)
        )

        XCTAssertEqual(result, NSRect(x: 200, y: 150, width: 600, height: 400))
    }

    func testSelectionAdjustmentBoundsPreventRevealingOutsideImage() throws {
        let selectionView = SelectionView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let imageFrame = NSRect(x: 100, y: 100, width: 200, height: 100)
        selectionView.updateSelectionRect(imageFrame)
        selectionView.selectionAdjustmentBounds = imageFrame

        selectionView.resizeByExternalDrag(
            handle: .topRight,
            originalRect: imageFrame,
            currentPoint: NSPoint(x: 450, y: 350)
        )

        XCTAssertEqual(try XCTUnwrap(selectionView.currentSelectionRect), imageFrame)
    }
}

@MainActor
final class FixedImageCropRendererTests: XCTestCase {
    override func tearDown() {
        ToastWindow.dismiss()
        super.tearDown()
    }

    func testEveryPresetImageSourceKeepsCropHandlesInteractive() throws {
        _ = NSApplication.shared
        let image = try makeTwoColorImage()
        let sources: [OverlayWindowController.PresetSource] = [
            .finder,
            .clipboard,
            .pin,
            .merge,
            .fullScreen,
        ]

        for source in sources {
            let controller = OverlayWindowController(
                presetImage: image,
                presetSource: source,
                onComplete: { _ in }
            )
            controller.activate()

            let selectionView = try XCTUnwrap(controller.activeSelectionViews.first)
            let originalRect = try XCTUnwrap(selectionView.currentSelectionRect)
            XCTAssertTrue(selectionView.selectionInteractionEnabled)
            XCTAssertEqual(selectionView.selectionAdjustmentBounds, originalRect)

            controller.cancel()
        }
    }

    func testPresetImageEditorExportsCroppedPixels() throws {
        _ = NSApplication.shared
        let image = try makeTwoColorImage()
        var completedImage: NSImage?
        let controller = OverlayWindowController(
            presetImage: image,
            presetSource: .pin
        ) { output in
            completedImage = output
        }
        controller.activate()
        defer { controller.cancel() }

        let selectionView = try XCTUnwrap(controller.activeSelectionViews.first)
        let originalRect = try XCTUnwrap(selectionView.currentSelectionRect)
        XCTAssertTrue(selectionView.selectionInteractionEnabled)
        XCTAssertEqual(selectionView.selectionAdjustmentBounds, originalRect)

        selectionView.resizeByExternalDrag(
            handle: .leftCenter,
            originalRect: originalRect,
            currentPoint: NSPoint(x: originalRect.midX, y: originalRect.midY)
        )
        selectionView.finalizeExternalResize()
        controller.confirmFromKeyboard()

        let cropped = try XCTUnwrap(completedImage)
        XCTAssertEqual(cropped.size, NSSize(width: 20, height: 20))
        assertColor(try pixelColor(in: cropped, x: 0, y: 0), matches: blue)
    }

    func testCropReturnsOnlyRequestedHorizontalPixels() throws {
        let image = try makeTwoColorImage()

        let left = try XCTUnwrap(
            FixedImageCropRenderer.crop(image, to: NSRect(x: 0, y: 0, width: 20, height: 20))
        )
        let right = try XCTUnwrap(
            FixedImageCropRenderer.crop(image, to: NSRect(x: 20, y: 0, width: 20, height: 20))
        )

        XCTAssertEqual(left.size, NSSize(width: 20, height: 20))
        XCTAssertEqual(right.size, NSSize(width: 20, height: 20))
        assertColor(try pixelColor(in: left, x: 0, y: 0), matches: red)
        assertColor(try pixelColor(in: right, x: 0, y: 0), matches: blue)
    }

    private func makeTwoColorImage() throws -> NSImage {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 40,
                pixelsHigh: 20,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = NSSize(width: 40, height: 20)
        for y in 0..<20 {
            for x in 0..<40 {
                bitmap.setColor(x < 20 ? red : blue, atX: x, y: y)
            }
        }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private var red: NSColor {
        NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
    }

    private var blue: NSColor {
        NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    }

    private func pixelColor(in image: NSImage, x: Int, y: Int) throws -> NSColor {
        let cgImage = try XCTUnwrap(image.cgImagePreservingBacking())
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return try XCTUnwrap(bitmap.colorAt(x: x, y: y))
    }

    private func assertColor(
        _ actual: NSColor,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualRGB = actual.usingColorSpace(.deviceRGB)
        let expectedRGB = expected.usingColorSpace(.deviceRGB)
        XCTAssertEqual(actualRGB?.redComponent ?? -1, expectedRGB?.redComponent ?? -2, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(actualRGB?.greenComponent ?? -1, expectedRGB?.greenComponent ?? -2, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(actualRGB?.blueComponent ?? -1, expectedRGB?.blueComponent ?? -2, accuracy: 0.02, file: file, line: line)
    }
}
