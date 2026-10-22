import AppKit
import CoreImage

final class TextQRCodeWindowController: NSWindowController, NSWindowDelegate {
    /// A conservative UTF-8 byte cap below the QR Code M-level payload limit
    /// keeps dense multi-byte text reliably scannable at the displayed size.
    static let maximumPayloadByteCount = 1_024

    private static var current: TextQRCodeWindowController?
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var outsideClickLocalMonitor: Any?
    private var outsideClickGlobalMonitor: Any?

    static func canGenerateQRCode(for text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return !data.isEmpty && data.count <= maximumPayloadByteCount
    }

    static func present(text: String, screen: NSScreen) {
        guard canGenerateQRCode(for: text), let image = makeQRCode(from: text) else { return }
        current?.close()
        let controller = TextQRCodeWindowController(text: text, qrCodeImage: image)
        current = controller
        controller.show(on: screen)
    }

    private init(text: String, qrCodeImage: NSImage) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.historyPreviewQRCodeTitle
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor

        super.init(window: panel)
        panel.delegate = self
        buildContent(text: text, qrCodeImage: qrCodeImage, in: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func show(on screen: NSScreen) {
        guard let window else { return }
        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        window.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startOutsideClickMonitoring()
    }

    func windowWillClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        if Self.current === self {
            Self.current = nil
        }
    }

    private func startOutsideClickMonitoring() {
        guard outsideClickLocalMonitor == nil, outsideClickGlobalMonitor == nil else { return }
        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            self?.closeForOutsideClickIfNeeded(event)
            return event
        }
        outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            self?.closeForOutsideClickIfNeeded(event)
        }
    }

    private func closeForOutsideClickIfNeeded(_ event: NSEvent) {
        guard let window,
              event.window !== window,
              event.windowNumber != window.windowNumber else { return }
        close()
    }

    private func stopOutsideClickMonitoring() {
        if let outsideClickLocalMonitor {
            NSEvent.removeMonitor(outsideClickLocalMonitor)
            self.outsideClickLocalMonitor = nil
        }
        if let outsideClickGlobalMonitor {
            NSEvent.removeMonitor(outsideClickGlobalMonitor)
            self.outsideClickGlobalMonitor = nil
        }
    }

    private func buildContent(text: String, qrCodeImage: NSImage, in panel: NSPanel) {
        guard let content = panel.contentView else { return }
        content.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let originalTitle = NSTextField(labelWithString: L10n.historyPreviewOriginalText)
        originalTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        originalTitle.textColor = .labelColor
        stack.addArrangedSubview(originalTitle)

        let textScrollView = AdaptiveQRCodeScrollView()
        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.drawsBackground = true
        textScrollView.backgroundColor = AdaptiveChrome.cardBackground
        textScrollView.borderType = .noBorder
        textScrollView.wantsLayer = true
        textScrollView.layer?.cornerRadius = 8
        textScrollView.layer?.cornerCurve = .continuous
        textScrollView.layer?.borderWidth = 1

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        textScrollView.documentView = textView
        stack.addArrangedSubview(textScrollView)

        let qrTitle = NSTextField(labelWithString: L10n.historyPreviewQRCodeTitle)
        qrTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        qrTitle.textColor = .labelColor
        stack.addArrangedSubview(qrTitle)

        let imageContainer = NSView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.wantsLayer = true
        imageContainer.layer?.backgroundColor = NSColor.white.cgColor
        imageContainer.layer?.cornerRadius = 12
        imageContainer.layer?.cornerCurve = .continuous
        stack.addArrangedSubview(imageContainer)

        let imageView = NSImageView(image: qrCodeImage)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setAccessibilityLabel(L10n.historyPreviewQRCodeTitle)
        imageContainer.addSubview(imageView)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),

            textScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            textScrollView.heightAnchor.constraint(equalToConstant: 150),

            imageContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            imageContainer.heightAnchor.constraint(equalToConstant: 390),

            imageView.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 350),
            imageView.heightAnchor.constraint(equalToConstant: 350),
        ])

        content.layoutSubtreeIfNeeded()
        textView.frame.size.width = textScrollView.contentSize.width
        textScrollView.contentView.scroll(to: .zero)
        textScrollView.reflectScrolledClipView(textScrollView.contentView)
    }

    private static func makeQRCode(from text: String) -> NSImage? {
        guard let data = text.data(using: .utf8), data.count <= maximumPayloadByteCount,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let targetPixelSize: CGFloat = 1_024
        let scale = max(1, floor(targetPixelSize / max(output.extent.width, output.extent.height)))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 350, height: 350))
    }
}

private final class AdaptiveQRCodeScrollView: NSScrollView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    private func applyAppearance() {
        backgroundColor = AdaptiveChrome.cardBackground
        layer?.borderColor = AdaptiveChrome.resolvedCGColor(
            AdaptiveChrome.border,
            for: effectiveAppearance
        )
    }
}
