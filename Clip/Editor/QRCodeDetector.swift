import CoreGraphics
import Vision

struct QRCodeDetection: Equatable {
    let payload: String
    /// Vision normalized rectangle, origin at the lower-left of the image.
    let normalizedBoundingBox: CGRect
}

enum QRCodeDetector {
    static func detect(in image: CGImage) -> [QRCodeDetection] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let observations = request.results ?? []
        return observations
            .compactMap { observation -> QRCodeDetection? in
                guard let payload = observation.payloadStringValue, !payload.isEmpty else {
                    return nil
                }
                return QRCodeDetection(
                    payload: payload,
                    normalizedBoundingBox: observation.boundingBox
                )
            }
            .sorted { lhs, rhs in
                let yDelta = lhs.normalizedBoundingBox.midY - rhs.normalizedBoundingBox.midY
                if abs(yDelta) > 0.01 {
                    return yDelta > 0
                }
                return lhs.normalizedBoundingBox.minX < rhs.normalizedBoundingBox.minX
            }
    }
}
