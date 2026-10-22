import AppKit
import XCTest
@testable import capcap

final class AgentContractTests: XCTestCase {
    func testScreenSelectorInfersScreenAndRejectsConflicts() throws {
        let options = try AgentCaptureOptions.parse(["--screen-index", "0", "--out", "/tmp/shot.png"])
        guard case .screen(let index, _) = options.target else { return XCTFail("Screen selector was ignored") }
        XCTAssertEqual(index, 0)
        XCTAssertThrowsError(try AgentCaptureOptions.parse(["--target", "mouse-screen", "--screen-index", "0", "--out", "/tmp/shot.png"]))
        XCTAssertThrowsError(try AgentCaptureOptions.parse(["--rect", "0,0,100,100", "--window-id", "42", "--out", "/tmp/shot.png"]))
        XCTAssertThrowsError(try AgentCaptureOptions.parse(["--out", "--pretty"]))
        XCTAssertThrowsError(try AgentCaptureOptions.parseRect("0,,0,100,100"))
    }

    func testOutputCannotOverwriteSpecOrMetadata() {
        XCTAssertThrowsError(try AgentRunOptions.parse(["--spec", "/tmp/marks.json", "--out", "/tmp/marks.json"]))
        XCTAssertThrowsError(try AgentCaptureOptions.parse(["--out", "/tmp/shot.png", "--meta", "/tmp/shot.png"]))
        XCTAssertThrowsError(try AgentIO.validatePaths(inputs: ["/tmp/source.png"], outputs: ["/tmp/./source.png"]))
    }

    func testSpecRejectsTyposAndWrongCoordinateArity() throws {
        for json in [
            #"{"annotations":[{"type":"text","at":[1,2],"text":"Hello","fontsize":24}]}"#,
            #"{"annotations":[{"type":"rect","rect":[1,2,3,4,5]}]}"#,
            #"{"annotations":[{"type":"arrow","from":[1,2],"to":{"x":3,"yy":4}}]}"#
        ] {
            XCTAssertThrowsError(try AgentSpecification.validateKeys(Data(json.utf8)))
        }
        let example = try XCTUnwrap(AgentSpecification.schema["example"])
        try AgentSpecification.validateKeys(JSONSerialization.data(withJSONObject: example))
    }
    func testEditorWindowIsIsolatedAndMenuKeepsBackdrop() {
        let editor = AgentWindowInfo(windowID: 1, ownerPID: 1, ownerName: "capcap", title: "", layer: 1000, frame: .zero)
        let menu = AgentWindowInfo(windowID: 2, ownerPID: 1, ownerName: "Control Center", title: "", layer: 25, frame: .zero)
        XCTAssertFalse(editor.usesCompositedScreenBackdrop)
        XCTAssertTrue(menu.usesCompositedScreenBackdrop)
    }

    func testDocumentedStylesAndPresentationRender() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let spec = directory.appendingPathComponent("marks.json")
        let out = directory.appendingPathComponent("out.png")
        let json = #"{"imageSize":[200,160],"crop":[10,20,180,120],"beautify":{"preset":"blue-purple","padding":20},"annotations":[{"type":"rect","rect":[20,30,40,50],"strokeStyle":"standard"},{"type":"arrow","from":[30,40],"to":[100,110],"style":"tapered"}]}"#
        try Data(json.utf8).write(to: spec)
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 200, height: 160))
        let result = try AgentAnnotator.annotate(baseImage: image, inputDescription: "test", specURL: spec, outputURL: out, command: "test", extraMetadata: [:])
        let dimensions = try XCTUnwrap(result.metadata["image"] as? [String: Int])
        XCTAssertEqual(dimensions["width"], 220)
        XCTAssertEqual(dimensions["height"], 160)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        try Data(json.replacingOccurrences(of: "[200,160]", with: "[201,160]").utf8).write(to: spec)
        XCTAssertThrowsError(try AgentAnnotator.annotate(baseImage: image, inputDescription: "test", specURL: spec, outputURL: out, command: "test", extraMetadata: [:]))
    }

}
