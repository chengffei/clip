import AppKit

/// Final presentation uses the same renderer as the interactive editor.
/// Marks always refer to the original input; crop and padding are applied last.
struct AgentImageFinish: Decodable {
    let crop: [Int]?
    let beautify: Beautify?

    struct Beautify: Decodable {
        let preset: String
        let padding: Int?
        let shadow: Bool?

        func resolvedPreset() throws -> BeautifyPreset {
            guard let value = BeautifyPreset.defaults.first(where: { $0.id == preset && !$0.isWallpaper }) else {
                throw AgentCLIError.failure("Unknown beautify preset \(preset); run agent schema for supported presets")
            }
            return value
        }
    }

    func validate(imageSize: NSSize) throws {
        if let crop {
            guard crop.count == 4, crop[0] >= 0, crop[1] >= 0, crop[2] > 0, crop[3] > 0,
                  Double(crop[0]) + Double(crop[2]) <= imageSize.width,
                  Double(crop[1]) + Double(crop[3]) <= imageSize.height else {
                throw AgentCLIError.failure("crop must be [x,y,width,height] in integer input pixels, fully inside the input image")
            }
        }
        if let beautify {
            _ = try beautify.resolvedPreset()
            if let padding = beautify.padding, !(0...512).contains(padding) {
                throw AgentCLIError.failure("beautify.padding must be an integer from 0 to 512 pixels")
            }
        }
    }

    func render(_ image: NSImage) throws -> NSImage {
        var result = image
        if let crop {
            guard let cg = image.cgImagePreservingBacking()?.cropping(to: CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3])) else {
                throw AgentCLIError.failure("Could not crop annotated image")
            }
            result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        if let beautify {
            guard let cg = result.cgImagePreservingBacking() else { throw AgentCLIError.failure("Could not prepare beautify input") }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            bitmap.size = NSSize(width: cg.width, height: cg.height)
            let pixelImage = NSImage(size: bitmap.size)
            pixelImage.addRepresentation(bitmap)
            result = BeautifyRenderer.render(innerImage: pixelImage, preset: try beautify.resolvedPreset(),
                padding: CGFloat(beautify.padding ?? 64), shadowEnabled: beautify.shadow ?? true)
        }
        return result
    }

    var metadata: [String: Any] {
        let padding = beautify.map { $0.padding ?? 64 } ?? 0
        var value: [String: Any] = ["order": ["annotate", "crop", "beautify"],
                                  "inputToOutputOffset": [padding - (crop?[0] ?? 0), padding - (crop?[1] ?? 0)]]
        if let crop { value["crop"] = crop }
        if let beautify { value["beautify"] = ["preset": beautify.preset, "padding": padding, "shadow": beautify.shadow ?? true] }
        return value
    }
}
