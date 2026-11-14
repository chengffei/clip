import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum ScreenRecordingFormat: String, CaseIterable {
    case mp4
    case gif

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .mp4: return L10n.recordingFormatMP4
        case .gif: return L10n.recordingFormatGIF
        }
    }
}

enum RecordingSavePreference: String, CaseIterable {
    case manual
    case gif
    case mp4

    var displayName: String {
        switch self {
        case .manual: return L10n.recordingFormatManual
        case .gif: return L10n.recordingFormatGIF
        case .mp4: return L10n.recordingFormatMP4
        }
    }

    var format: ScreenRecordingFormat? {
        switch self {
        case .manual: return nil
        case .gif: return .gif
        case .mp4: return .mp4
        }
    }
}

typealias RecordingProgressCallback = (_ seconds: Int) -> Void
typealias RecordingCompletionCallback = (_ url: URL?, _ error: Error?) -> Void

final class RecordingEngine: NSObject {
    enum State {
        case idle
        case recording
        case paused
        case stopping
    }

    private(set) var state: State = .idle

    private let fps: Int
    private let recordingQueue = DispatchQueue(label: "clip.recording")

    private var screen: NSScreen?
    private var sourceRect: CGRect = .zero
    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?
    private var outputURL: URL?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private let captureActive = LockedFlag()
    private let capturePaused = LockedFlag()
    private let pausedDuration = LockedTimeInterval()

    private var hasWrittenFrame = false

    private var progressTimer: Timer?
    private var elapsedSeconds = 0
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0

    var onProgress: RecordingProgressCallback?
    var onCompletion: RecordingCompletionCallback?
    var onPauseChanged: ((Bool) -> Void)?

    init(fps: Int = 30) {
        self.fps = fps
    }

    func startRecording(
        rect: NSRect,
        screen: NSScreen,
        excludeWindowNumbers: [CGWindowID] = []
    ) {
        guard state == .idle else { return }
        guard rect.width > 0, rect.height > 0 else {
            fail(RecordingError.invalidSelection)
            return
        }

        self.state = .recording
        self.screen = screen
        self.totalPausedDuration = 0
        self.pauseStartTime = nil
        self.hasWrittenFrame = false
        self.captureActive.set(true)
        self.capturePaused.set(false)
        self.pausedDuration.set(0)

        sourceRect = CGRect(
            x: rect.minX - screen.frame.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        Task { @MainActor [weak self] in
            await self?.beginCapture(
                screen: screen,
                excludeWindowNumbers: excludeWindowNumbers
            )
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }
        state = .paused
        pauseStartTime = Date()
        capturePaused.set(true)
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
            self?.onPauseChanged?(true)
        }
    }

    func resumeRecording() {
        guard state == .paused else { return }
        if let pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStartTime)
            pausedDuration.set(totalPausedDuration)
            self.pauseStartTime = nil
        }
        state = .recording
        capturePaused.set(false)
        DispatchQueue.main.async { [weak self] in
            self?.startProgressTimer()
            self?.onPauseChanged?(false)
        }
    }

    func stopRecording() {
        guard state == .recording || state == .paused else { return }
        state = .stopping
        captureActive.set(false)
        capturePaused.set(false)
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
        }
        Task { @MainActor [weak self] in
            await self?.finalizeCapture()
        }
    }

    func cancelRecording() {
        guard state == .recording || state == .paused else { return }
        state = .stopping
        captureActive.set(false)
        capturePaused.set(false)
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
        }
        Task { @MainActor [weak self] in
            await self?.cancelCapture()
        }
    }

    @MainActor
    private func beginCapture(
        screen: NSScreen,
        excludeWindowNumbers: [CGWindowID]
    ) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard captureActive.get() else { return }

            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first else {
                fail(RecordingError.noDisplay)
                return
            }

            let excludedWindows = excludeWindowNumbers.compactMap { windowID in
                content.windows.first(where: { $0.windowID == windowID })
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

            let scale = max(screen.backingScaleFactor, 1)
            let (pixelWidth, pixelHeight) = VideoEncodingSettings.evenDimensions(
                width: sourceRect.width * scale,
                height: sourceRect.height * scale
            )

            let config = SCStreamConfiguration()
            config.sourceRect = sourceRect
            config.width = pixelWidth
            config.height = pixelHeight
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.showsCursor = true
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.scalesToFit = false
            // Frames go to the encoder as the stream's own buffers; a deeper
            // pool keeps the stream delivering while VideoToolbox still
            // holds a burst of them.
            config.queueDepth = 6
            if #available(macOS 14.0, *) {
                config.colorSpaceName = CGColorSpace.sRGB
            }

            let outputURL = Self.makeOutputURL()
            self.outputURL = outputURL
            try prepareWriter(
                url: outputURL,
                width: pixelWidth,
                height: pixelHeight
            )
            guard captureActive.get() else {
                cleanupTemporaryOutput()
                return
            }

            let output = RecordingStreamOutput()
            output.onFrame = { [weak self] pixelBuffer, presentationTime in
                self?.handleFrame(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
            }
            output.onStopped = { [weak self] in
                self?.stopRecording()
            }
            streamOutput = output

            let stream = SCStream(filter: filter, configuration: config, delegate: output)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: recordingQueue)
            guard captureActive.get() else {
                cleanupTemporaryOutput()
                return
            }
            try await stream.startCapture()
            self.stream = stream
            DispatchQueue.main.async { [weak self] in
                self?.elapsedSeconds = 0
                self?.onProgress?(0)
                self?.startProgressTimer()
            }
        } catch {
            fail(error)
        }
    }

    private func prepareWriter(
        url: URL,
        width: Int,
        height: Int
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: VideoEncodingSettings.outputSettings(width: width, height: height, fps: fps)
        )
        input.expectsMediaDataInRealTime = true

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        guard writer.canAdd(input) else { throw RecordingError.writerSetupFailed }
        writer.add(input)
        writer.startWriting()

        self.assetWriter = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.sessionStarted = false
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard captureActive.get(), !capturePaused.get() else { return }
        writeMP4Frame(pixelBuffer: pixelBuffer, presentationTime: adjustedTime(presentationTime))
    }

    private func writeMP4Frame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let input = videoInput,
              let adaptor = adaptor,
              input.isReadyForMoreMediaData
        else { return }

        if !sessionStarted {
            startWriterSession(at: presentationTime)
        }

        if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            hasWrittenFrame = true
        }
    }

    private func startWriterSession(at time: CMTime) {
        guard let writer = assetWriter, !sessionStarted else { return }
        writer.startSession(atSourceTime: time)
        sessionStarted = true
    }

    private func adjustedTime(_ time: CMTime) -> CMTime {
        let totalPausedDuration = pausedDuration.get()
        guard totalPausedDuration > 0 else { return time }
        return CMTimeSubtract(
            time,
            CMTimeMakeWithSeconds(totalPausedDuration, preferredTimescale: time.timescale)
        )
    }

    @MainActor
    private func finalizeCapture() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        streamOutput = nil
        recordingQueue.sync {}

        await finalizeMP4()
    }

    @MainActor
    private func cancelCapture() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        streamOutput = nil
        recordingQueue.sync {}
        cleanupTemporaryOutput()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.onCompletion?(nil, nil)
        }
    }

    @MainActor
    private func finalizeMP4() async {
        guard let writer = assetWriter, let input = videoInput else {
            fail(RecordingError.writerSetupFailed)
            return
        }

        input.markAsFinished()
        await writer.finishWriting()

        assetWriter = nil
        videoInput = nil
        adaptor = nil

        if let error = writer.error {
            fail(error)
        } else if !hasWrittenFrame {
            fail(RecordingError.noFrames)
        } else {
            succeed()
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        // `.common` so the HUD clock keeps ticking while a menu is open.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds += 1
            self.onProgress?(self.elapsedSeconds)
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func succeed() {
        let url = outputURL
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.captureActive.set(false)
            self.capturePaused.set(false)
            self.state = .idle
            self.onCompletion?(url, nil)
        }
    }

    private func fail(_ error: Error) {
        captureActive.set(false)
        capturePaused.set(false)
        recordingQueue.sync {}
        cleanupTemporaryOutput()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            self.state = .idle
            self.onCompletion?(nil, error)
        }
    }

    private func cleanupTemporaryOutput() {
        let url = outputURL
        assetWriter?.cancelWriting()
        assetWriter = nil
        videoInput = nil
        adaptor = nil
        outputURL = nil
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let date = formatter.string(from: Date())
        let token = ProcessInfo.processInfo.globallyUniqueString
            .replacingOccurrences(of: "/", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-recording-\(date)-\(token).mp4")
    }

    enum RecordingError: LocalizedError {
        case invalidSelection
        case noDisplay
        case noFrames
        case writerSetupFailed

        var errorDescription: String? {
            switch self {
            case .invalidSelection: return "The selected recording area is empty"
            case .noDisplay: return "Could not find the selected display"
            case .noFrames: return "No video frames were recorded"
            case .writerSetupFailed: return "Could not prepare the recording writer"
            }
        }
    }
}

private final class RecordingStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onStopped: (() -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onStopped?()
        }
    }
}
/// Thread-safe boolean shared between the main thread and the sample queues.
private final class LockedFlag {
    private var value: Bool
    private let lock = NSLock()

    init(_ value: Bool = false) {
        self.value = value
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private final class LockedTimeInterval {
    private var value: TimeInterval = 0
    private let lock = NSLock()

    func get() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: TimeInterval) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
