import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum RecordingExporter {
    static func exportGIF(
        from videoURL: URL,
        to destinationURL: URL,
        fps: Int = 15,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            let exportTask = Task.detached(priority: .userInitiated) {
                try await exportGIFInBackground(from: videoURL, to: destinationURL, fps: fps)
            }
            let result: Result<Void, Error>
            do {
                try await exportTask.value
                result = .success(())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func exportGIFInBackground(from videoURL: URL, to destinationURL: URL, fps: Int) async throws {
        do {
            try? FileManager.default.removeItem(at: destinationURL)

            let asset = AVURLAsset(url: videoURL)
            guard let videoTrack = try await VideoAssetMetadata.loadFirstVideoTrack(in: asset) else {
                throw ExportError.missingVideoTrack
            }
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            )
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else {
                throw ExportError.readerSetupFailed
            }
            reader.add(output)

            let sourceFPS = normalizedSourceFPS(nominalFrameRate)
            let encoder = GIFEncoder(url: destinationURL, fps: fps, sourceFPS: sourceFPS)

            guard reader.startReading() else {
                throw reader.error ?? ExportError.readerFailed
            }

            var frameCount = 0
            while reader.status == .reading {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                encoder.addFrame(pixelBuffer)
                frameCount += 1
            }

            if reader.status == .failed || reader.status == .cancelled {
                throw reader.error ?? ExportError.readerFailed
            }
            guard frameCount > 0 else {
                throw ExportError.noFrames
            }
            guard encoder.finish() else {
                throw ExportError.gifFinalizeFailed
            }
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func normalizedSourceFPS(_ nominalFrameRate: Float) -> Int {
        let rounded = Int(nominalFrameRate.rounded())
        return rounded > 0 ? rounded : 30
    }

    enum ExportError: LocalizedError {
        case missingVideoTrack
        case readerSetupFailed
        case readerFailed
        case noFrames
        case gifFinalizeFailed

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return "The recording did not contain a video track"
            case .readerSetupFailed:
                return "Could not prepare the recording for GIF export"
            case .readerFailed:
                return "Could not read the recording frames"
            case .noFrames:
                return "No video frames were available for GIF export"
            case .gifFinalizeFailed:
                return "Could not finish writing the GIF"
            }
        }
    }
}
