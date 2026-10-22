import AudioToolbox
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

/// Audio source options the engine can capture alongside video. Both audio
/// tracks are always created so the HUD toggles work live mid-recording;
/// a track that never receives a sample is dropped from the output file.
struct RecordingAudioOptions {
    var systemAudio: Bool
    var microphone: Bool
    /// UID of the CoreAudio input device to use for the microphone. nil means
    /// the system default input device.
    var microphoneDeviceUID: String? = nil

    static let none = RecordingAudioOptions(systemAudio: false, microphone: false)
}

enum RecordingAudioTimeline {
    static func silenceFrameChunks(
        from start: CMTime,
        to end: CMTime,
        sampleRate: Double,
        maximumFramesPerChunk: Int
    ) -> [Int] {
        guard start.isValid,
              end.isValid,
              sampleRate > 0,
              maximumFramesPerChunk > 0,
              CMTimeCompare(start, end) < 0
        else { return [] }

        let timescale = CMTimeScale(sampleRate.rounded())
        guard timescale > 0 else { return [] }
        let duration = CMTimeSubtract(end, start)
        let durationInFrames = CMTimeConvertScale(
            duration,
            timescale: timescale,
            method: .roundTowardZero
        )
        guard durationInFrames.value > 0 else { return [] }

        var remaining = Int(durationInFrames.value)
        var chunks: [Int] = []
        while remaining > 0 {
            let frameCount = min(remaining, maximumFramesPerChunk)
            chunks.append(frameCount)
            remaining -= frameCount
        }
        return chunks
    }
}

enum RecordingMicrophoneActivationPolicy {
    static func shouldStartCapture(
        isEnabled: Bool,
        hasRecorder: Bool,
        isRecording: Bool,
        trackArmed: Bool
    ) -> Bool {
        isEnabled && !hasRecorder && isRecording && trackArmed
    }
}

struct RecordingSystemAudioCaptureState {
    private(set) var desiredEnabled = false
    private(set) var appliedEnabled = false
    private(set) var updateInFlight = false

    var mayWriteAudio: Bool {
        desiredEnabled && appliedEnabled && !updateInFlight
    }

    mutating func reset(desiredEnabled: Bool) {
        self.desiredEnabled = desiredEnabled
        appliedEnabled = false
        updateInFlight = false
    }

    mutating func install(appliedEnabled: Bool) {
        self.appliedEnabled = appliedEnabled
        updateInFlight = false
    }

    mutating func request(_ enabled: Bool) {
        desiredEnabled = enabled
    }

    mutating func beginNextUpdate() -> Bool? {
        guard !updateInFlight, desiredEnabled != appliedEnabled else { return nil }
        updateInFlight = true
        return desiredEnabled
    }

    mutating func completeUpdate(appliedEnabled: Bool) {
        self.appliedEnabled = appliedEnabled
        updateInFlight = false
    }

    @discardableResult
    mutating func failUpdate() -> Bool {
        desiredEnabled = appliedEnabled
        updateInFlight = false
        return appliedEnabled
    }
}

final class RecordingEngine: NSObject {
    enum State {
        case idle
        case recording
        case paused
        case stopping
    }

    private(set) var state: State = .idle

    private let fps: Int
    private let recordingQueue = DispatchQueue(label: "capcap.recording")

    private var screen: NSScreen?
    private var sourceRect: CGRect = .zero
    private var stream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?
    private var streamOutput: RecordingStreamOutput?
    private var outputURL: URL?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var sessionStarted = false
    /// Session anchor PTS — the timeline origin silence backfill starts from.
    private var referenceAnchor: CMTime?
    private var hasWrittenSystemAudio = false
    private var hasWrittenMicrophone = false
    private var lastSystemAudioEndTime: CMTime?
    private var lastMicrophoneEndTime: CMTime?
    private var audioOptions: RecordingAudioOptions = .none

    private var microphoneRecorder: MicrophoneRecorder?
    /// The writer has a mic input but the recorder isn't running (mic was off
    /// at start) — a live HUD enable starts the recorder lazily.
    private var microphoneTrackArmed = false
    private let microphoneEnabled = LockedFlag()
    private let microphoneGeneration = LockedInteger()
    private let systemAudioMuted = LockedFlag()
    private let captureActive = LockedFlag()
    private let capturePaused = LockedFlag()
    private let pausedDuration = LockedTimeInterval()

    private var systemAudioCaptureState = RecordingSystemAudioCaptureState()
    private var streamConfigurationGeneration = 0

    /// Enable or disable system-audio delivery for the current stream. The
    /// mute gate closes immediately; ScreenCaptureKit stops delivering audio
    /// once the asynchronous configuration update completes.
    func setSystemAudioEnabled(_ enabled: Bool) {
        audioOptions.systemAudio = enabled
        systemAudioCaptureState.request(enabled)
        updateSystemAudioMuteGate()
        scheduleSystemAudioConfigurationUpdate()
    }

    /// Enable or disable microphone capture for the current recording. Turning
    /// it off pauses AVAudioEngine instead of continuing to receive voice data.
    func setMicrophoneEnabled(_ enabled: Bool) {
        audioOptions.microphone = enabled
        microphoneEnabled.set(enabled)

        if let recorder = microphoneRecorder {
            if enabled, state == .recording {
                do {
                    try recorder.resume()
                } catch {
                    handleMicrophoneStartFailure(error)
                }
            } else {
                recorder.pause()
            }
        } else if RecordingMicrophoneActivationPolicy.shouldStartCapture(
            isEnabled: enabled,
            hasRecorder: false,
            isRecording: state == .recording,
            trackArmed: microphoneTrackArmed
        ) {
            startMicrophoneRecording()
        }
    }

    /// Apply an input-device choice to the active recording as well as future
    /// lazy microphone starts.
    func setMicrophoneDeviceUID(_ uid: String?) {
        guard audioOptions.microphoneDeviceUID != uid else { return }
        audioOptions.microphoneDeviceUID = uid

        guard state == .recording || state == .paused else { return }
        stopMicrophoneRecording()
        if RecordingMicrophoneActivationPolicy.shouldStartCapture(
            isEnabled: microphoneEnabled.get(),
            hasRecorder: false,
            isRecording: state == .recording,
            trackArmed: microphoneTrackArmed
        ) {
            startMicrophoneRecording()
        }
    }

    private func updateSystemAudioMuteGate() {
        systemAudioMuted.set(!systemAudioCaptureState.mayWriteAudio)
    }

    private func scheduleSystemAudioConfigurationUpdate() {
        guard captureActive.get(),
              let stream,
              let currentConfiguration = streamConfiguration,
              let updatedConfiguration = currentConfiguration.copy() as? SCStreamConfiguration
        else {
            updateSystemAudioMuteGate()
            return
        }

        guard let targetEnabled = systemAudioCaptureState.beginNextUpdate() else {
            updateSystemAudioMuteGate()
            return
        }
        let generation = streamConfigurationGeneration
        updatedConfiguration.capturesAudio = targetEnabled
        updateSystemAudioMuteGate()

        Task { @MainActor [weak self] in
            do {
                try await stream.updateConfiguration(updatedConfiguration)
                guard let self,
                      self.streamConfigurationGeneration == generation,
                      self.stream === stream
                else { return }

                self.streamConfiguration = updatedConfiguration
                self.systemAudioCaptureState.completeUpdate(appliedEnabled: targetEnabled)
                self.updateSystemAudioMuteGate()
                self.scheduleSystemAudioConfigurationUpdate()
            } catch {
                guard let self,
                      self.streamConfigurationGeneration == generation,
                      self.stream === stream
                else { return }

                let appliedEnabled = self.systemAudioCaptureState.failUpdate()
                self.audioOptions.systemAudio = appliedEnabled
                self.updateSystemAudioMuteGate()
                self.onSystemAudioConfigurationFailed?(appliedEnabled)
            }
        }
    }

    private func invalidateSystemAudioConfigurationUpdates() {
        streamConfigurationGeneration += 1
        streamConfiguration = nil
        systemAudioCaptureState.reset(desiredEnabled: false)
        systemAudioMuted.set(true)
    }

    private var hasWrittenFrame = false

    private var progressTimer: Timer?
    private var elapsedSeconds = 0
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0

    var onProgress: RecordingProgressCallback?
    var onCompletion: RecordingCompletionCallback?
    var onPauseChanged: ((Bool) -> Void)?
    var onSystemAudioConfigurationFailed: ((_ appliedEnabled: Bool) -> Void)?
    var onMicrophoneCaptureFailed: (() -> Void)?

    init(fps: Int = 30) {
        self.fps = fps
    }

    func startRecording(
        rect: NSRect,
        screen: NSScreen,
        excludeWindowNumbers: [CGWindowID] = [],
        audioOptions: RecordingAudioOptions = .none
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
        self.hasWrittenSystemAudio = false
        self.hasWrittenMicrophone = false
        self.lastSystemAudioEndTime = nil
        self.lastMicrophoneEndTime = nil
        self.microphoneTrackArmed = false
        self.microphoneEnabled.set(audioOptions.microphone)
        self.captureActive.set(true)
        self.capturePaused.set(false)
        self.pausedDuration.set(0)
        self.systemAudioCaptureState.reset(desiredEnabled: audioOptions.systemAudio)
        self.systemAudioMuted.set(true)
        self.audioOptions = audioOptions

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
        microphoneRecorder?.pause()
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
        if microphoneEnabled.get() {
            if let recorder = microphoneRecorder {
                do {
                    try recorder.resume()
                } catch {
                    handleMicrophoneStartFailure(error)
                }
            } else if RecordingMicrophoneActivationPolicy.shouldStartCapture(
                isEnabled: true,
                hasRecorder: false,
                isRecording: state == .recording,
                trackArmed: microphoneTrackArmed
            ) {
                startMicrophoneRecording()
            }
        }
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
        invalidateSystemAudioConfigurationUpdates()
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
        invalidateSystemAudioConfigurationUpdates()
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
            // Respect the visible audio state at the capture boundary. Live
            // toggles update this configuration instead of receiving and
            // discarding system audio while the control is off.
            config.capturesAudio = self.audioOptions.systemAudio
            config.sampleRate = 44_100
            config.channelCount = 2
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.scalesToFit = false
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
            output.onAudioSampleBuffer = { [weak self] sampleBuffer in
                self?.handleSystemAudioSampleBuffer(sampleBuffer)
            }
            output.onStopped = { [weak self] in
                self?.stopRecording()
            }
            streamOutput = output

            let stream = SCStream(filter: filter, configuration: config, delegate: output)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: recordingQueue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: recordingQueue)
            guard captureActive.get() else {
                cleanupTemporaryOutput()
                return
            }
            try await stream.startCapture()
            self.stream = stream
            self.streamConfiguration = config
            self.streamConfigurationGeneration += 1
            self.systemAudioCaptureState.install(appliedEnabled: config.capturesAudio)
            self.systemAudioCaptureState.request(self.audioOptions.systemAudio)
            updateSystemAudioMuteGate()
            scheduleSystemAudioConfigurationUpdate()

            microphoneTrackArmed = true
            if self.audioOptions.microphone {
                startMicrophoneRecording()
            }

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

        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: RecordingAudioSettings.systemAudioOutputSettings
        )
        audioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(audioInput) else { throw RecordingError.writerSetupFailed }
        writer.add(audioInput)
        self.systemAudioInput = audioInput

        let micInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: RecordingAudioSettings.microphoneOutputSettings
        )
        micInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(micInput) else { throw RecordingError.writerSetupFailed }
        writer.add(micInput)
        self.microphoneInput = micInput

        writer.startWriting()

        self.assetWriter = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.sessionStarted = false
        self.referenceAnchor = nil
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

    private func handleSystemAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard captureActive.get(),
              !capturePaused.get(),
              !systemAudioMuted.get(),
              let input = systemAudioInput
        else { return }

        let presentationTime = adjustedTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if !sessionStarted {
            startWriterSession(at: presentationTime)
        }

        guard input.isReadyForMoreMediaData else { return }
        let gapStart = lastSystemAudioEndTime ?? referenceAnchor
        if let gapStart, CMTimeCompare(gapStart, presentationTime) < 0 {
            let fill = appendSilence(
                into: input,
                like: sampleBuffer,
                from: gapStart,
                to: presentationTime
            )
            lastSystemAudioEndTime = fill.lastEnd
            guard fill.completed else { return }
        }

        guard let restamped = restamp(sampleBuffer, to: presentationTime) else { return }
        guard input.append(restamped) else { return }
        hasWrittenSystemAudio = true
        lastSystemAudioEndTime = sampleEndTime(
            presentationTime: presentationTime,
            sampleBuffer: restamped
        )
    }

    private func handleMicrophoneSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard captureActive.get(),
              !capturePaused.get(),
              microphoneEnabled.get(),
              let input = microphoneInput
        else { return }

        let presentationTime = adjustedTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if !sessionStarted {
            startWriterSession(at: presentationTime)
        }

        guard input.isReadyForMoreMediaData else { return }
        let gapStart = lastMicrophoneEndTime ?? referenceAnchor
        if let gapStart, CMTimeCompare(gapStart, presentationTime) < 0 {
            let fill = appendSilence(
                into: input,
                like: sampleBuffer,
                from: gapStart,
                to: presentationTime
            )
            lastMicrophoneEndTime = fill.lastEnd
            guard fill.completed else { return }
        }

        guard let restamped = restamp(sampleBuffer, to: presentationTime) else { return }
        guard input.append(restamped) else { return }
        hasWrittenMicrophone = true
        lastMicrophoneEndTime = sampleEndTime(
            presentationTime: presentationTime,
            sampleBuffer: restamped
        )
    }

    private struct SilenceAppendResult {
        let lastEnd: CMTime
        let completed: Bool
    }

    /// Writes zeroed PCM covering the whole-frame portion of [start, end).
    /// The final buffer is shortened to the exact remaining frame count so it
    /// never overlaps the real sample that starts at `end`.
    private func appendSilence(
        into input: AVAssetWriterInput,
        like reference: CMSampleBuffer,
        from start: CMTime,
        to end: CMTime
    ) -> SilenceAppendResult {
        guard start.isValid, end.isValid, CMTimeCompare(start, end) < 0,
              let formatDescription = CMSampleBufferGetFormatDescription(reference),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
              asbd.mSampleRate > 0
        else {
            return SilenceAppendResult(lastEnd: start, completed: true)
        }

        let framesPerChunk = max(1, CMSampleBufferGetNumSamples(reference))
        let chunks = RecordingAudioTimeline.silenceFrameChunks(
            from: start,
            to: end,
            sampleRate: asbd.mSampleRate,
            maximumFramesPerChunk: framesPerChunk
        )
        var cursor = start
        for frameCount in chunks {
            guard input.isReadyForMoreMediaData else {
                return SilenceAppendResult(lastEnd: cursor, completed: false)
            }
            guard let silent = Self.makeSilence(
                like: reference, at: cursor,
                frameCount: frameCount,
                formatDescription: formatDescription,
                asbd: asbd
            ), input.append(silent)
            else {
                return SilenceAppendResult(lastEnd: cursor, completed: false)
            }
            cursor = CMTimeAdd(
                cursor,
                CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(asbd.mSampleRate))
            )
        }
        return SilenceAppendResult(lastEnd: cursor, completed: true)
    }

    private static func makeSilence(
        like reference: CMSampleBuffer,
        at pts: CMTime,
        frameCount: Int,
        formatDescription: CMAudioFormatDescription,
        asbd: AudioStreamBasicDescription
    ) -> CMSampleBuffer? {
        guard let sourceBlock = CMSampleBufferGetDataBuffer(reference) else { return nil }
        let referenceLength = CMBlockBufferGetDataLength(sourceBlock)
        let referenceFrameCount = CMSampleBufferGetNumSamples(reference)
        guard referenceLength > 0, referenceFrameCount > 0, frameCount > 0 else { return nil }
        let bytesPerFrame = referenceLength / referenceFrameCount
        let length = bytesPerFrame * frameCount
        guard bytesPerFrame > 0, length > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        guard CMBlockBufferFillDataBytes(
            with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: length
        ) == kCMBlockBufferNoErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleSize = bytesPerFrame
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer,
            formatDescription: formatDescription, sampleCount: frameCount,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }

    private func sampleEndTime(
        presentationTime: CMTime,
        sampleBuffer: CMSampleBuffer
    ) -> CMTime {
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        if duration.isValid, CMTimeCompare(duration, .zero) > 0 {
            return CMTimeAdd(presentationTime, duration)
        }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
              asbd.mSampleRate > 0
        else { return presentationTime }
        return CMTimeAdd(
            presentationTime,
            CMTime(
                value: CMTimeValue(CMSampleBufferGetNumSamples(sampleBuffer)),
                timescale: CMTimeScale(asbd.mSampleRate)
            )
        )
    }

    private func startWriterSession(at time: CMTime) {
        guard let writer = assetWriter, !sessionStarted else { return }
        writer.startSession(atSourceTime: time)
        referenceAnchor = time
        sessionStarted = true
    }

    /// Re-stamps a sample buffer's PTS onto the pause-adjusted timeline so
    /// audio and video stay continuous across pause/resume.
    private func restamp(_ sampleBuffer: CMSampleBuffer, to presentationTime: CMTime) -> CMSampleBuffer? {
        var timingCount = CMItemCount()
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        )
        let originalDuration: CMTime
        if timingCount > 0 {
            var originalTiming = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: Int(timingCount))
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: timingCount,
                arrayToFill: &originalTiming,
                entriesNeededOut: &timingCount
            )
            originalDuration = originalTiming.first?.duration ?? .invalid
        } else {
            originalDuration = .invalid
        }

        var newTiming = CMSampleTimingInfo(
            duration: originalDuration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &newTiming,
            sampleBufferOut: &newBuffer
        )
        guard status == noErr else { return nil }
        return newBuffer
    }

    private func startMicrophoneRecording() {
        guard RecordingMicrophoneActivationPolicy.shouldStartCapture(
            isEnabled: microphoneEnabled.get(),
            hasRecorder: microphoneRecorder != nil,
            isRecording: state == .recording,
            trackArmed: microphoneTrackArmed
        )
        else { return }

        let generation = microphoneGeneration.increment()
        let recorder = MicrophoneRecorder(deviceUID: audioOptions.microphoneDeviceUID)
        recorder.onSampleBuffer = { [weak self] sampleBuffer in
            guard let self else { return }
            self.recordingQueue.async { [weak self] in
                guard let self,
                      self.microphoneGeneration.get() == generation
                else { return }
                self.handleMicrophoneSampleBuffer(sampleBuffer)
            }
        }
        self.microphoneRecorder = recorder
        do {
            try recorder.start()
        } catch {
            handleMicrophoneStartFailure(error)
        }
    }

    private func stopMicrophoneRecording() {
        _ = microphoneGeneration.increment()
        microphoneRecorder?.stop()
        microphoneRecorder = nil
        microphoneTrackArmed = true
    }

    private func handleMicrophoneStartFailure(_ error: Error) {
        stopMicrophoneRecording()
        microphoneEnabled.set(false)
        audioOptions.microphone = false
        DispatchQueue.main.async { [weak self] in
            self?.onMicrophoneCaptureFailed?()
        }
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
        stopMicrophoneRecording()
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
        stopMicrophoneRecording()
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
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()

        assetWriter = nil
        videoInput = nil
        adaptor = nil
        systemAudioInput = nil
        microphoneInput = nil

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
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds += 1
            self.onProgress?(self.elapsedSeconds)
        }
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
        invalidateSystemAudioConfigurationUpdates()
        stopMicrophoneRecording()
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
        systemAudioInput = nil
        microphoneInput = nil
        lastSystemAudioEndTime = nil
        lastMicrophoneEndTime = nil
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
            .appendingPathComponent("capcap-recording-\(date)-\(token).mp4")
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
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onStopped: (() -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
            onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        case .audio:
            guard sampleBuffer.numSamples > 0 else { return }
            onAudioSampleBuffer?(sampleBuffer)
        case .microphone:
            // SCStream doesn't capture microphone directly — capcap routes it
            // through AVAudioEngine via MicrophoneRecorder instead.
            break
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onStopped?()
        }
    }
}

/// Captures microphone audio via AVAudioEngine (SCStream has no mic capture
/// on macOS) and converts PCM buffers into CMSampleBuffers for the writer.
private final class MicrophoneRecorder {
    enum RecorderError: LocalizedError {
        case audioUnitUnavailable
        case inputFormatUnavailable
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .audioUnitUnavailable:
                return "The selected microphone is unavailable"
            case .inputFormatUnavailable:
                return "The microphone input format is unavailable"
            case .converterUnavailable:
                return "The microphone audio converter could not be created"
            }
        }
    }

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let deviceUID: String?
    private var paused = false
    private var tapInstalled = false

    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    init(deviceUID: String?) {
        self.deviceUID = deviceUID
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44_100,
            channels: 1,
            interleaved: true
        )!
    }

    /// Starts microphone capture or throws so the HUD can report that the
    /// visible enabled state was not actually applied.
    func start() throws {
        // Select the user's chosen device BEFORE querying the input format —
        // the format depends on the device.
        if let deviceUID, let deviceID = AudioInputDevices.deviceID(forUID: deviceUID) {
            guard let audioUnit = engine.inputNode.audioUnit else {
                throw RecorderError.audioUnitUnavailable
            }
            var id = deviceID
            // Best-effort: on failure the system default input is used.
            _ = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioObjectID>.size)
            )
        }

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.inputFormatUnavailable
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.converterUnavailable
        }
        self.converter = converter

        do {
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.handle(buffer: buffer)
            }
            tapInstalled = true
            try engine.start()
        } catch {
            stop()
            throw error
        }
    }

    func pause() {
        guard !paused else { return }
        paused = true
        engine.pause()
    }

    func resume() throws {
        guard paused else { return }
        try engine.start()
        paused = false
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        paused = false
    }

    private func handle(buffer: AVAudioPCMBuffer) {
        guard !paused else { return }

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        )
        guard frameCapacity > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity)
        else { return }

        var conversionError: NSError?
        var supplied = false
        guard let converter else { return }
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil else { return }

        if let sampleBuffer = Self.makeSampleBuffer(from: converted, format: outputFormat) {
            onSampleBuffer?(sampleBuffer)
        }
    }

    private static func makeSampleBuffer(
        from buffer: AVAudioPCMBuffer,
        format: AVAudioFormat
    ) -> CMSampleBuffer? {
        var formatDescription: CMAudioFormatDescription?
        var basicDescription = format.streamDescription.pointee
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &basicDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        // Copy the PCM bytes into a CMBlockBuffer the sample buffer owns;
        // AVAudioPCMBuffer's backing memory may be reused before the writer
        // drains the queue. NOTE: `int16ChannelData` points to the *channel
        // pointer array* — subscript [0] to reach the actual PCM storage.
        var blockBuffer: CMBlockBuffer?
        let dataByteSize = Int(buffer.frameLength) * Int(format.streamDescription.pointee.mBytesPerFrame)
        guard dataByteSize > 0,
              let channelData = buffer.int16ChannelData?[0]
        else { return nil }

        let allocationStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataByteSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataByteSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard allocationStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        let replaceStatus = CMBlockBufferReplaceDataBytes(
            with: channelData,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: dataByteSize
        )
        guard replaceStatus == kCMBlockBufferNoErr else { return nil }

        // sampleSizeArray is UnsafePointer<Int> on macOS 14, not Int32.
        let sampleSize = MemoryLayout<Int16>.size
        var sampleSizes: [Int] = [sampleSize]
        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizes,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else { return nil }

        // Stamp with the host-time clock so mic PTS shares SCStream's clock
        // domain and the engine can re-stamp it onto the recording timeline.
        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var timedBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &timedBuffer
        )
        return timedBuffer ?? sampleBuffer
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

private final class LockedInteger {
    private var value = 0
    private let lock = NSLock()

    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        value += 1
        let result = value
        lock.unlock()
        return result
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

enum RecordingAudioSettings {
    /// Output settings for system audio captured via SCStream. Matches the
    /// 44.1kHz stereo format requested in `SCStreamConfiguration`.
    static var systemAudioOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }

    /// Output settings for microphone audio captured via AVAudioEngine.
    /// Single channel matches typical microphone input.
    static var microphoneOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }
}
