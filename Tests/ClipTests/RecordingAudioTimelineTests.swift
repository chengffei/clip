import CoreMedia
import XCTest
@testable import capcap

final class RecordingAudioTimelineTests: XCTestCase {
    func testSilenceChunksShortenFinalBufferWithoutCrossingRealSample() {
        let start = CMTime.zero
        let end = CMTime(value: 1, timescale: 10)

        let chunks = RecordingAudioTimeline.silenceFrameChunks(
            from: start,
            to: end,
            sampleRate: 44_100,
            maximumFramesPerChunk: 1_024
        )

        XCTAssertEqual(chunks, [1_024, 1_024, 1_024, 1_024, 314])
        XCTAssertEqual(chunks.reduce(0, +), 4_410)
        XCTAssertLessThanOrEqual(chunks.last ?? 0, 1_024)
    }

    func testSilenceChunksDropOnlySubframeRemainder() {
        let start = CMTime.zero
        let end = CMTime(value: 1, timescale: 100_000)

        let chunks = RecordingAudioTimeline.silenceFrameChunks(
            from: start,
            to: end,
            sampleRate: 44_100,
            maximumFramesPerChunk: 1_024
        )

        XCTAssertTrue(chunks.isEmpty)
    }

    func testSilenceChunksResumeFromPartialBackfillBoundary() {
        let start = CMTime(value: 2_048, timescale: 44_100)
        let end = CMTime(value: 5_000, timescale: 44_100)

        let chunks = RecordingAudioTimeline.silenceFrameChunks(
            from: start,
            to: end,
            sampleRate: 44_100,
            maximumFramesPerChunk: 1_024
        )

        XCTAssertEqual(chunks, [1_024, 1_024, 904])
        XCTAssertEqual(chunks.reduce(0, +), 2_952)
    }
}

final class RecordingMicrophoneActivationPolicyTests: XCTestCase {
    func testPausedLazyEnableStartsAfterResume() {
        XCTAssertFalse(
            RecordingMicrophoneActivationPolicy.shouldStartCapture(
                isEnabled: true,
                hasRecorder: false,
                isRecording: false,
                trackArmed: true
            )
        )
        XCTAssertTrue(
            RecordingMicrophoneActivationPolicy.shouldStartCapture(
                isEnabled: true,
                hasRecorder: false,
                isRecording: true,
                trackArmed: true
            )
        )
    }

    func testExistingRecorderIsNeverStartedTwice() {
        XCTAssertFalse(
            RecordingMicrophoneActivationPolicy.shouldStartCapture(
                isEnabled: true,
                hasRecorder: true,
                isRecording: true,
                trackArmed: true
            )
        )
    }

    func testDisabledOrUnarmedMicrophoneDoesNotStart() {
        XCTAssertFalse(
            RecordingMicrophoneActivationPolicy.shouldStartCapture(
                isEnabled: false,
                hasRecorder: false,
                isRecording: true,
                trackArmed: true
            )
        )
        XCTAssertFalse(
            RecordingMicrophoneActivationPolicy.shouldStartCapture(
                isEnabled: true,
                hasRecorder: false,
                isRecording: true,
                trackArmed: false
            )
        )
    }
}

final class RecordingSystemAudioCaptureStateTests: XCTestCase {
    func testDisabledStateNeverAllowsAudioWrites() {
        var state = RecordingSystemAudioCaptureState()
        state.reset(desiredEnabled: false)
        state.install(appliedEnabled: false)

        XCTAssertFalse(state.mayWriteAudio)
        XCTAssertNil(state.beginNextUpdate())
    }

    func testEnableKeepsGateClosedUntilConfigurationApplies() {
        var state = RecordingSystemAudioCaptureState()
        state.reset(desiredEnabled: false)
        state.install(appliedEnabled: false)
        state.request(true)

        XCTAssertEqual(state.beginNextUpdate(), true)
        XCTAssertFalse(state.mayWriteAudio)

        state.completeUpdate(appliedEnabled: true)
        XCTAssertTrue(state.mayWriteAudio)
    }

    func testRapidDisableDuringEnableSchedulesASecondTransition() {
        var state = RecordingSystemAudioCaptureState()
        state.reset(desiredEnabled: false)
        state.install(appliedEnabled: false)
        state.request(true)

        XCTAssertEqual(state.beginNextUpdate(), true)
        state.request(false)
        state.completeUpdate(appliedEnabled: true)

        XCTAssertFalse(state.mayWriteAudio)
        XCTAssertEqual(state.beginNextUpdate(), false)
        state.completeUpdate(appliedEnabled: false)
        XCTAssertFalse(state.mayWriteAudio)
        XCTAssertNil(state.beginNextUpdate())
    }

    func testFailedTransitionRevertsToAppliedState() {
        var state = RecordingSystemAudioCaptureState()
        state.reset(desiredEnabled: false)
        state.install(appliedEnabled: false)
        state.request(true)

        XCTAssertEqual(state.beginNextUpdate(), true)
        XCTAssertFalse(state.failUpdate())
        XCTAssertFalse(state.desiredEnabled)
        XCTAssertFalse(state.mayWriteAudio)
    }
}
