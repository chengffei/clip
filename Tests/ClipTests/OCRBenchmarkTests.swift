import AppKit
import Vision
import XCTest
@testable import Clip

/// Times Vision text recognition on a synthetic dense screenshot so OCR
/// tuning decisions rest on numbers from this machine. Runs only when
/// `CLIP_OCR_BENCH` is set; prints one line per configuration.
final class OCRBenchmarkTests: XCTestCase {
    func testVisionConfigurationsTiming() throws {
        guard ProcessInfo.processInfo.environment["CLIP_OCR_BENCH"] != nil else { return }
        _ = NSApplication.shared
        let image = Self.denseScreenshot()
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        print("BENCH image px \(cg.width)x\(cg.height)")

        func bench(_ label: String, on cgImage: CGImage, _ configure: (VNRecognizeTextRequest) -> Void) {
            for round in 1...2 {
                let request = VNRecognizeTextRequest()
                configure(request)
                let start = Date()
                try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                let seconds = Date().timeIntervalSince(start)
                print(String(format: "BENCH %-44@ round %d: %.2fs lines %d", label, round, seconds, request.results?.count ?? 0))
            }
        }
        let coldFirst = ProcessInfo.processInfo.environment["CLIP_OCR_BENCH"] == "zh-en-first"
        if coldFirst {
            bench("COLD accurate+corr, zh-Hans+en-US", on: cg) { r in
                r.recognitionLevel = .accurate; r.usesLanguageCorrection = true; r.recognitionLanguages = ["zh-Hans", "en-US"]
            }
        }
        bench("current: accurate+corr+5 langs+autodetect", on: cg) { r in
            r.recognitionLevel = .accurate; r.usesLanguageCorrection = true
            r.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]; r.automaticallyDetectsLanguage = true
        }
        bench("accurate+corr, zh-Hans+en-US", on: cg) { r in
            r.recognitionLevel = .accurate; r.usesLanguageCorrection = true; r.recognitionLanguages = ["zh-Hans", "en-US"]
        }
        bench("accurate, no corr, zh-Hans+en-US", on: cg) { r in
            r.recognitionLevel = .accurate; r.usesLanguageCorrection = false; r.recognitionLanguages = ["zh-Hans", "en-US"]
        }
        bench("fast+corr, zh-Hans+en-US", on: cg) { r in
            r.recognitionLevel = .fast; r.usesLanguageCorrection = true; r.recognitionLanguages = ["zh-Hans", "en-US"]
        }
        let small = try XCTUnwrap(Self.downscaled(cg, maxSide: 1600))
        print("BENCH small px \(small.width)x\(small.height)")
        bench("accurate+corr, zh-Hans+en-US, 1600px", on: small) { r in
            r.recognitionLevel = .accurate; r.usesLanguageCorrection = true; r.recognitionLanguages = ["zh-Hans", "en-US"]
        }
    }

    private static func denseScreenshot() -> NSImage {
        let size = NSSize(width: 1300, height: 1000)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .regular),
            .foregroundColor: NSColor(white: 0.9, alpha: 1),
        ]
        let lines = [
            "过了 htmlhint 和 proto-lint。没开浏览器手点，点击效果没验证。",
            "件，版本 v6.29，保留 Settings 和 Feed-in 两站。",
            "和底部 Device Tab，点了只弹提示 Opens the Devices tab，不再跳转。",
            "ess/product-rebels/workspace/felix/prototypes/Site-Settings-Rest",
            "ess/product-rebels/requirements/intake/PRD-App-Site-Settings-Res",
            "字段都还指向旧 slug /demo/site-settings/，需要你说「发布」才会更新",
            "调研、蓝图里的旧原型链接没改。",
            "one 3:14 PM",
        ]
        return NSImage(size: size, flipped: false) { _ in
            NSColor(white: 0.16, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            for i in 0..<22 {
                (lines[i % lines.count] as NSString).draw(
                    at: NSPoint(x: 30, y: size.height - 50 - CGFloat(i) * 42), withAttributes: attrs)
            }
            return true
        }
    }

    private static func downscaled(_ cg: CGImage, maxSide: Int) -> CGImage? {
        let longest = max(cg.width, cg.height)
        guard longest > maxSide else { return cg }
        let scale = Double(maxSide) / Double(longest)
        let w = Int(Double(cg.width) * scale), h = Int(Double(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
