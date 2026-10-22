import AppKit

/// Coordinates the active upload: shows the floating progress chip, runs the
/// provider upload, copies the URL on success, surfaces a toast either way.
final class UploadManager {
    static let shared = UploadManager()

    private var inFlight = false
    private var progressWindow: UploadProgressWindow?

    private init() {}

    func upload(image: NSImage, on screen: NSScreen?) {
        guard !inFlight else { return }
        guard let kind = Defaults.defaultUploadProviderKind else {
            ToastWindow.show(message: L10n.uploadNoProvider, on: screen)
            return
        }
        guard let config = ProviderConfigStore.load(kind: kind) else {
            ToastWindow.show(message: L10n.uploadNoProvider, on: screen)
            return
        }
        let providerType = Uploaders.provider(for: kind)
        if let err = providerType.validate(config) {
            ToastWindow.show(message: err, on: screen)
            return
        }
        inFlight = true
        let quality = Defaults.screenshotUploadQuality
        if quality.usesLossyCompression {
            ToastWindow.show(message: L10n.screenshotQualityCompressingUpload, on: screen, duration: 600)
        }

        ImageOutputEncoder.encodeAsync(image: image, quality: quality) { [weak self] result in
            guard let self else { return }
            if quality.usesLossyCompression {
                ToastWindow.dismiss()
            }

            switch result {
            case .failure:
                self.inFlight = false
                HistoryManager.shared.add(image: image)
                ToastWindow.show(message: L10n.screenshotCompressionFailed, on: screen, duration: 3.0)
            case .success(let output):
                let fileName = FilenameTemplate.imageFileName(
                    for: image,
                    fileExtension: output.fileExtension,
                    imageSize: output.pixelSize
                )

                let window = UploadProgressWindow(provider: kind.displayName)
                window.show(on: screen)
                self.progressWindow = window

                providerType.upload(
                    data: output.data,
                    fileName: fileName,
                    contentType: output.contentType,
                    config: config,
                    progress: { [weak self] pct in
                        self?.progressWindow?.setProgress(pct)
                    },
                    completion: { [weak self] result in
                        guard let self else { return }
                        self.inFlight = false
                        self.progressWindow?.dismiss()
                        self.progressWindow = nil
                        switch result {
                        case .success(let url):
                            let asMarkdown = Defaults.copyUploadAsMarkdown
                            let copyText = asMarkdown
                                ? "![](\(url.absoluteString))"
                                : url.absoluteString
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(copyText, forType: .string)
                            HistoryManager.shared.add(image: image, cloudURL: url)
                            ToastWindow.show(
                                message: asMarkdown ? L10n.uploadCopiedMarkdown : L10n.uploadCopied,
                                on: screen
                            )
                        case .failure(let err):
                            HistoryManager.shared.add(image: image)
                            let msg = (err as? UploadError)?.errorDescription
                                ?? err.localizedDescription
                            ToastWindow.show(message: "\(L10n.uploadFailedPrefix) \(msg)", on: screen)
                        }
                    }
                )
            }
        }
    }

}
