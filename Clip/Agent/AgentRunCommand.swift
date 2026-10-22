import AppKit
import CoreGraphics
import Foundation

struct AgentRunOptions {
    let target: AgentCaptureTarget
    let specURL: URL
    let outputURL: URL
    let shotOutputURL: URL?
    let metaURL: URL?
    let pretty: Bool

    static func parse(_ arguments: [String]) throws -> AgentRunOptions {
        var targetName: String?
        var spec: String?
        var output: String?
        var shotOutput: String?
        var meta: String?
        var pretty = false
        var rect: CGRect?
        var windowID: CGWindowID?
        var screenIndex: Int?
        var displayID: CGDirectDisplayID?

        var index = 0
        while index < arguments.count {
            let token = arguments[index]

            if token == "--pretty" {
                pretty = true
                index += 1
                continue
            }
            if token == "--help" || token == "-h" {
                throw AgentCLIError.help(Self.usageText)
            }

            let key: String
            let value: String

            if let split = token.firstIndex(of: "="), token.hasPrefix("--") {
                key = String(token[..<split])
                value = String(token[token.index(after: split)...])
                index += 1
            } else {
                key = token
                guard index + 1 < arguments.count else {
                    throw AgentCLIError.usage("Missing value for \(token)")
                }
                guard !arguments[index + 1].hasPrefix("--"), arguments[index + 1] != "-h" else {
                    throw AgentCLIError.usage("Missing value for \(token)")
                }
                value = arguments[index + 1]
                index += 2
            }

            switch key {
            case "--target", "-t":
                targetName = value
            case "--spec", "-s":
                spec = value
            case "--out", "--output", "-o":
                output = value
            case "--shot-out":
                shotOutput = value
            case "--meta":
                meta = value
            case "--rect":
                rect = try AgentCaptureOptions.parseRect(value)
            case "--window-id":
                windowID = try AgentCaptureOptions.parseWindowID(value)
            case "--screen-index", "--screen":
                guard let parsed = Int(value), parsed >= 0 else {
                    throw AgentCLIError.usage("Invalid screen index \(value)")
                }
                screenIndex = parsed
            case "--display-id":
                displayID = try AgentCaptureOptions.parseDisplayID(value)
            default:
                throw AgentCLIError.usage("Unknown option \(key)")
            }
        }

        guard let spec else { throw AgentCLIError.usage("Missing --spec") }
        guard let output else { throw AgentCLIError.usage("Missing --out") }

        try AgentIO.validatePaths(inputs: [spec], outputs: [output] + [shotOutput, meta].compactMap { $0 })
        let outputURL = AgentIO.fileURL(from: output)
        let shotOutputURL = shotOutput.map(AgentIO.fileURL(from:))
        if let shotOutputURL, shotOutputURL == outputURL {
            throw AgentCLIError.usage("--shot-out must be different from --out")
        }

        let target = try AgentCaptureTarget.resolve(
            targetName: targetName,
            rect: rect,
            windowID: windowID,
            screenIndex: screenIndex,
            displayID: displayID
        )

        return AgentRunOptions(
            target: target,
            specURL: AgentIO.fileURL(from: spec),
            outputURL: outputURL,
            shotOutputURL: shotOutputURL,
            metaURL: meta.map(AgentIO.fileURL(from:)),
            pretty: pretty
        )
    }

    private static let usageText = """
    Usage
      capcap agent run --target mouse-screen --spec marks.json --out result.png
      capcap agent run --target rect --rect 0,0,800,600 --spec marks.json --out result.png --shot-out shot.png

    Targets
      screen
      mouse-screen
      rect
      window-id
      window-at-cursor
      frontmost-window

    Options
      --target, -t       Capture target
      --spec, -s         JSON annotation spec
      --out, -o          Output annotated PNG file
      --shot-out         Optional raw capture PNG file
      --meta             Optional metadata JSON file
      --rect             Global CG rect as x,y,width,height
      --window-id        WindowServer window ID
      --screen-index     Screen index for screen target
      --display-id       CGDirectDisplayID for screen target
      --pretty           Pretty print JSON output
    """
}

struct AgentRunResult {
    let metadata: [String: Any]
}

enum AgentRunner {
    static func run(options: AgentRunOptions) throws -> AgentRunResult {
        let capture = try AgentCapturer.capturePayload(for: options.target)
        let annotationImage = try imageUsingPixelDimensions(capture.image)

        if let shotOutputURL = options.shotOutputURL {
            try writeRawShot(capture.image, to: shotOutputURL)
        }

        var extraMetadata: [String: Any] = [
            "capture": capture.metadata
        ]
        if let shotOutputURL = options.shotOutputURL {
            extraMetadata["shotOut"] = shotOutputURL.path
        }

        let annotateResult = try AgentAnnotator.annotate(
            baseImage: annotationImage,
            inputDescription: "agent capture",
            specURL: options.specURL,
            outputURL: options.outputURL,
            command: "agent run",
            extraMetadata: extraMetadata
        )

        return AgentRunResult(metadata: annotateResult.metadata)
    }

    private static func imageUsingPixelDimensions(_ image: NSImage) throws -> NSImage {
        guard let cgImage = image.cgImagePreservingBacking() else {
            throw AgentCLIError.failure("Could not prepare captured image for annotation")
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private static func writeRawShot(_ image: NSImage, to url: URL) throws {
        guard let pngData = image.pngDataPreservingBacking() else {
            throw AgentCLIError.failure("Could not encode raw capture PNG")
        }
        try AgentIO.ensureParentDirectory(for: url)
        do {
            try pngData.write(to: url, options: .atomic)
        } catch {
            throw AgentCLIError.failure("Could not write raw capture \(url.path)")
        }
    }
}
