import AppKit
import XCTest
@testable import capcap

@MainActor
final class PinWindowInteractionTests: XCTestCase {
    func testImagePinAcceptsActivationMouseDown() {
        let view = PinContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))

        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    func testTransparentImagePinDoesNotAddASecondWindowShadow() throws {
        let image = try Self.makeImage(edgeAlpha: 0)

        XCTAssertFalse(PinLauncher.shouldUseSystemWindowShadow(for: image))
    }

    func testOpaqueImagePinKeepsSystemWindowShadow() throws {
        let image = try Self.makeImage(edgeAlpha: 255)

        XCTAssertTrue(PinLauncher.shouldUseSystemWindowShadow(for: image))
    }

    func testPinImageScalingKeepsTheFullAspectRatioAtLargeZoomLevels() {
        let baseSize = NSSize(width: 1_200, height: 800)

        let scaledSize = PinImageLayout.scaledSize(baseSize: baseSize, scale: 3.5)

        XCTAssertEqual(scaledSize.width, 4_200, accuracy: 0.001)
        XCTAssertEqual(scaledSize.height, 2_800, accuracy: 0.001)
        XCTAssertEqual(
            scaledSize.width / scaledSize.height,
            baseSize.width / baseSize.height,
            accuracy: 0.000_001
        )
    }

    func testPinImageScalingKeepsExtremeAspectRatios() {
        let baseSize = NSSize(width: 1, height: 100)

        let scaledSize = PinImageLayout.scaledSize(baseSize: baseSize, scale: 0.25)

        XCTAssertEqual(scaledSize.width, 0.25, accuracy: 0.001)
        XCTAssertEqual(scaledSize.height, 25, accuracy: 0.001)
        XCTAssertEqual(
            scaledSize.width / scaledSize.height,
            baseSize.width / baseSize.height,
            accuracy: 0.000_001
        )
    }

    func testPinImageFocusedZoomKeepsTheSameImagePointUnderThePointer() {
        let currentFrame = NSRect(x: 120, y: 240, width: 400, height: 200)
        let focus = NSPoint(x: 0.25, y: 0.75)

        let resizedFrame = PinImageLayout.resizedFrame(
            from: currentFrame,
            to: NSSize(width: 800, height: 400),
            focusing: focus
        )

        XCTAssertEqual(
            resizedFrame.minX + resizedFrame.width * focus.x,
            currentFrame.minX + currentFrame.width * focus.x,
            accuracy: 0.001
        )
        XCTAssertEqual(
            resizedFrame.minY + resizedFrame.height * focus.y,
            currentFrame.minY + currentFrame.height * focus.y,
            accuracy: 0.001
        )
    }

    func testPinToolbarIsInsetInsideTheImageTopLeftCorner() {
        let imageBounds = NSRect(x: 0, y: 0, width: 800, height: 500)

        let toolbarFrame = PinImageLayout.toolbarFrame(
            in: imageBounds,
            preferredSize: NSSize(
                width: PinToolbarView.preferredWidth,
                height: PinToolbarView.preferredHeight
            )
        )

        XCTAssertEqual(toolbarFrame.minX, 8, accuracy: 0.001)
        XCTAssertEqual(toolbarFrame.maxY, imageBounds.maxY - 8, accuracy: 0.001)
        XCTAssertTrue(imageBounds.contains(toolbarFrame))
    }

    func testPinToolbarUsesOpaqueContentBoundsInsteadOfShadowPadding() throws {
        let image = try Self.makeImage(
            width: 100,
            height: 80,
            opaqueRect: CGRect(x: 10, y: 8, width: 80, height: 60),
            backgroundAlpha: 96
        )
        let normalizedContentRect = PinImageLayout.normalizedContentRect(for: image)
        let contentRect = PinImageLayout.contentRect(
            in: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            normalizedContentRect: normalizedContentRect
        )

        let toolbarFrame = PinImageLayout.toolbarFrame(
            in: contentRect,
            preferredSize: NSSize(
                width: PinToolbarView.preferredWidth,
                height: PinToolbarView.preferredHeight
            )
        )
        let contentView = PinContentView(
            frame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        contentView.image = NSImage(
            cgImage: image,
            size: NSSize(width: 1_000, height: 800)
        )
        let toolbar = try XCTUnwrap(
            contentView.subviews.first { $0 is PinToolbarView } as? PinToolbarView
        )

        XCTAssertEqual(contentRect, NSRect(x: 100, y: 120, width: 800, height: 600))
        XCTAssertEqual(toolbarFrame.minX, 108, accuracy: 0.001)
        XCTAssertEqual(toolbarFrame.maxY, 712, accuracy: 0.001)
        XCTAssertTrue(contentRect.contains(toolbarFrame))
        XCTAssertEqual(toolbar.frame, toolbarFrame)
    }

    func testOpaquePinImageKeepsTheWholeImageAsContentBounds() throws {
        let image = try Self.makeImage(
            width: 100,
            height: 80,
            opaqueRect: CGRect(x: 0, y: 0, width: 100, height: 80),
            backgroundAlpha: 255
        )

        let normalizedContentRect = PinImageLayout.normalizedContentRect(for: image)

        XCTAssertEqual(normalizedContentRect, PinImageLayout.fullNormalizedContentRect)
    }

    func testPinToolbarProvidesCopyAndDragWithoutMoveControl() throws {
        let toolbar = PinToolbarView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: PinToolbarView.preferredWidth,
                height: PinToolbarView.preferredHeight
            )
        )
        toolbar.layoutSubtreeIfNeeded()
        let buttons = toolbar.subviews.compactMap { $0 as? NSButton }
        let labels = buttons.compactMap { $0.accessibilityLabel() }
        let copyButton = try XCTUnwrap(
            buttons.first { $0.accessibilityLabel() == L10n.pinToolbarCopy }
        )
        let closeButton = try XCTUnwrap(
            buttons.first { $0.accessibilityLabel() == L10n.pinToolbarClose }
        )
        var didCopy = false
        toolbar.onCopy = { didCopy = true }

        copyButton.performClick(nil)

        XCTAssertEqual(buttons.count, 6)
        XCTAssertTrue(labels.contains(L10n.pinToolbarCopy))
        XCTAssertTrue(labels.contains(L10n.pinToolbarDrag))
        XCTAssertFalse(labels.contains("Move pinned image"))
        XCTAssertEqual(closeButton.frame.size, copyButton.frame.size)
        XCTAssertEqual(closeButton.contentTintColor, .systemRed)
        let closeBackground = try XCTUnwrap(closeButton.layer?.backgroundColor)
        XCTAssertEqual(closeBackground.alpha, 0, accuracy: 0.001)
        XCTAssertTrue(didCopy)
    }

    func testPinToolbarHidesOptionalButtonsFromLeftToRight() {
        let toolbar = PinToolbarView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: PinToolbarView.preferredWidth,
                height: PinToolbarView.preferredHeight
            )
        )

        assertVisiblePinToolbarItems(
            in: toolbar,
            width: 191,
            optionalLabels: [L10n.pinToolbarEdit, L10n.tipOCR, L10n.pinToolbarCopy]
        )
        assertVisiblePinToolbarItems(
            in: toolbar,
            width: 163,
            optionalLabels: [L10n.tipOCR, L10n.pinToolbarCopy]
        )
        assertVisiblePinToolbarItems(
            in: toolbar,
            width: 135,
            optionalLabels: [L10n.pinToolbarCopy]
        )
        assertVisiblePinToolbarItems(
            in: toolbar,
            width: 107,
            optionalLabels: []
        )
        assertVisiblePinToolbarItems(
            in: toolbar,
            width: 79,
            optionalLabels: []
        )
    }

    func testPinCopyWritesPNGAndTIFFToPasteboard() throws {
        let image = try Self.makeImage(edgeAlpha: 255)
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("capcap.pin-copy-tests.\(UUID().uuidString)")
        )

        ClipboardManager.copyToClipboard(image: image, pasteboard: pasteboard)

        XCTAssertNotNil(pasteboard.data(forType: .png))
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
    }

    func testPinDragButtonStartsOnlyAfterPointerMovement() throws {
        let toolbar = PinToolbarView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: PinToolbarView.preferredWidth,
                height: PinToolbarView.preferredHeight
            )
        )
        let window = NSWindow(
            contentRect: toolbar.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = toolbar
        toolbar.layoutSubtreeIfNeeded()
        let dragButton = try XCTUnwrap(
            toolbar.subviews
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityLabel() == L10n.pinToolbarDrag }
        )
        let start = dragButton.convert(NSPoint(x: 2, y: 2), to: nil)
        let mouseDown = try XCTUnwrap(Self.mouseEvent(type: .leftMouseDown, at: start))
        let smallMove = try XCTUnwrap(
            Self.mouseEvent(
                type: .leftMouseDragged,
                at: NSPoint(x: start.x + 2, y: start.y)
            )
        )
        let dragMove = try XCTUnwrap(
            Self.mouseEvent(
                type: .leftMouseDragged,
                at: NSPoint(x: start.x + 5, y: start.y)
            )
        )
        var dragCount = 0
        toolbar.onDrag = { _ in dragCount += 1 }

        dragButton.mouseDown(with: mouseDown)
        dragButton.mouseDragged(with: smallMove)
        XCTAssertEqual(dragCount, 0)

        dragButton.mouseDragged(with: dragMove)
        XCTAssertEqual(dragCount, 1)
    }

    func testPinDragPayloadProvidesImageDataAndTemporaryPNGFile() throws {
        let image = try Self.makeImage(edgeAlpha: 255)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "capcap-pin-drag-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = try XCTUnwrap(PinImageDragPayload.make(from: image, in: directory))
        let fileURLString = try XCTUnwrap(
            payload.pasteboardItem.string(forType: .fileURL)
        )
        let pasteboardFileURL = try XCTUnwrap(URL(string: fileURLString))
        let pngData = try XCTUnwrap(payload.pasteboardItem.data(forType: .png))
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("capcap.pin-drag-tests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([payload.pasteboardItem]))
        let readableFileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]

        XCTAssertEqual(pasteboardFileURL.standardizedFileURL, payload.temporaryFileURL.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: payload.temporaryFileURL), pngData)
        XCTAssertNotNil(payload.pasteboardItem.data(forType: .tiff))
        XCTAssertEqual(readableFileURLs?.first?.standardizedFileURL, payload.temporaryFileURL.standardizedFileURL)
        XCTAssertNotNil(NSImage(pasteboard: pasteboard))
    }

    private static func mouseEvent(type: NSEvent.EventType, at point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    private func assertVisiblePinToolbarItems(
        in toolbar: PinToolbarView,
        width: CGFloat,
        optionalLabels: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        toolbar.setFrameSize(
            NSSize(width: width, height: PinToolbarView.preferredHeight)
        )
        toolbar.layoutSubtreeIfNeeded()
        let visibleLabels = toolbar.subviews
            .compactMap { $0 as? NSButton }
            .filter { !$0.isHidden }
            .compactMap { $0.accessibilityLabel() }

        XCTAssertTrue(
            visibleLabels.contains(L10n.pinToolbarClose),
            file: file,
            line: line
        )
        XCTAssertTrue(visibleLabels.contains("100%"), file: file, line: line)
        XCTAssertEqual(
            visibleLabels.filter { $0 != L10n.pinToolbarClose && $0 != "100%" },
            optionalLabels,
            file: file,
            line: line
        )
    }

    private static func makeImage(edgeAlpha: UInt8) throws -> NSImage {
        let width = 3
        let height = 3
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where x == 0 || x == width - 1 || y == 0 || y == height - 1 {
                let offset = (y * width + x) * 4
                pixels[offset] = edgeAlpha
                pixels[offset + 1] = edgeAlpha
                pixels[offset + 2] = edgeAlpha
                pixels[offset + 3] = edgeAlpha
            }
        }

        let cgImage = pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return context?.makeImage()
        }
        return NSImage(
            cgImage: try XCTUnwrap(cgImage),
            size: NSSize(width: width, height: height)
        )
    }

    private static func makeImage(
        width: Int,
        height: Int,
        opaqueRect: CGRect,
        backgroundAlpha: UInt8
    ) throws -> CGImage {
        var pixels = [UInt8](repeating: backgroundAlpha, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = backgroundAlpha
                pixels[offset + 1] = backgroundAlpha
                pixels[offset + 2] = backgroundAlpha
                pixels[offset + 3] = backgroundAlpha

                if opaqueRect.contains(CGPoint(x: x, y: y)) {
                    pixels[offset] = 255
                    pixels[offset + 1] = 255
                    pixels[offset + 2] = 255
                    pixels[offset + 3] = 255
                }
            }
        }

        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
    }
}
