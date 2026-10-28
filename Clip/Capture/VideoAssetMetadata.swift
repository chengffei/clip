import AVFoundation
import CoreGraphics

enum VideoAssetMetadata {
    static func loadFirstVideoTrack(in asset: AVAsset) async throws -> AVAssetTrack? {
        try await asset.loadTracks(withMediaType: .video).first
    }


}
