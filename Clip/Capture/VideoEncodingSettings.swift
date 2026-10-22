import AVFoundation

enum VideoQuality {
    case high

    var bitsPerPixelPerFrame: Double {
        switch self {
        case .high: return 0.21
        }
    }

    var minBitrate: Int {
        switch self {
        case .high: return 3_000_000
        }
    }

    var maxBitrate: Int {
        switch self {
        case .high: return 80_000_000
        }
    }
}

enum VideoEncodingSettings {
    static func outputSettings(width: Int, height: Int, fps: Int, quality: VideoQuality = .high) -> [String: Any] {
        let bitrate = Self.bitrate(width: width, height: height, fps: fps, quality: quality)
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: max(fps, 1),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
            ],
        ]
    }

    static func evenDimensions(width: CGFloat, height: CGFloat) -> (Int, Int) {
        // Round UP to the next even integer. The naive `(n / 2) * 2` truncates
        // odd integers back down (1921 -> 1920), defeating `.rounded(.up)` and
        // capturing a frame one pixel smaller than the source. Adding 1 first
        // makes odd inputs round up (1921 -> 1922) while even inputs are
        // unchanged (1920 -> 1920).
        let w = ((Int(width.rounded(.up)) + 1) / 2) * 2
        let h = ((Int(height.rounded(.up)) + 1) / 2) * 2
        return (max(w, 2), max(h, 2))
    }

    private static func bitrate(width: Int, height: Int, fps: Int, quality: VideoQuality) -> Int {
        guard width > 0, height > 0, fps > 0 else { return quality.minBitrate }
        let pixels = Double(width) * Double(height)
        let raw = pixels * Double(fps) * quality.bitsPerPixelPerFrame
        let taper: Double
        if pixels > 3840 * 2160 {
            taper = 0.80
        } else if pixels > 1920 * 1080 {
            taper = 0.92
        } else {
            taper = 1.0
        }
        let clamped = min(max(raw * taper, Double(quality.minBitrate)), Double(quality.maxBitrate))
        return Int(clamped.rounded())
    }
}
