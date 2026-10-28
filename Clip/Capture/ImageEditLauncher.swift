import AppKit

enum ImageEditLauncher {


    /// Hands an in-memory generated image off to the existing editor. Used by
    /// workflows such as Image Merge where the source image is not a file or
    /// the live clipboard.
    static func launch(
        generatedImage image: NSImage,
        source: OverlayWindowController.PresetSource = .merge,
        keepsEditorAcrossSpaces: Bool = false,
        onRequestFocusReturn: (() -> Void)? = nil,
        onSuspend: ((OverlayWindowController.SuspendedEditDraft) -> Void)? = nil,
        onComplete: @escaping (NSImage?) -> Void
    ) -> OverlayWindowController? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return present(
            image,
            source: source,
            keepsEditorAcrossSpaces: keepsEditorAcrossSpaces,
            onRequestFocusReturn: onRequestFocusReturn,
            onSuspend: onSuspend,
            onComplete: onComplete
        )
    }

    private static func present(
        _ image: NSImage,
        source: OverlayWindowController.PresetSource,
        keepsEditorAcrossSpaces: Bool = false,
        onRequestFocusReturn: (() -> Void)?,
        onSuspend: ((OverlayWindowController.SuspendedEditDraft) -> Void)?,
        onComplete: @escaping (NSImage?) -> Void
    ) -> OverlayWindowController? {
        let controller = OverlayWindowController(
            presetImage: image,
            presetSource: source,
            keepsEditorAcrossSpaces: keepsEditorAcrossSpaces,
            onRequestFocusReturn: onRequestFocusReturn,
            onSuspend: onSuspend,
            onComplete: onComplete
        )
        controller.activate()
        return controller
    }


    // MARK: - Helpers



}
