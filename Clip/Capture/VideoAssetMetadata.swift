import AVFoundation
import CoreGraphics

enum VideoAssetMetadata {
    static func loadFirstVideoTrack(in asset: AVAsset) async throws -> AVAssetTrack? {
        try await asset.loadTracks(withMediaType: .video).first
    }

    static func pixelSize(for url: URL) async throws -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try await loadFirstVideoTrack(in: asset) else { return nil }
        return try await pixelSize(for: track)
    }

    static func pixelSize(for track: AVAssetTrack) async throws -> CGSize? {
        let (naturalSize, preferredTransform) = try await (
            track.load(.naturalSize),
            track.load(.preferredTransform)
        )
        let transformed = naturalSize.applying(preferredTransform)
        let size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }
}
