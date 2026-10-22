import Foundation
import XCTest
@testable import capcap

final class HistorySearchMatcherTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func testAllScopeMatchesColorAndTextButNeverMedia() throws {
        let text = try textEntry("Release Café")
        let color = colorEntry("#FF6A23")
        let image = HistoryEntry(
            fileURL: directoryURL.appendingPathComponent("image.png"),
            createdAt: Date(),
            kind: .image,
            cloudURL: nil
        )

        XCTAssertTrue(HistorySearchMatcher.matches(text, query: "cafe", scope: .colorsAndText))
        XCTAssertTrue(HistorySearchMatcher.matches(color, query: "ff6a", scope: .colorsAndText))
        XCTAssertFalse(HistorySearchMatcher.matches(image, query: "image", scope: .colorsAndText))
    }

    func testColorScopeExcludesMatchingText() throws {
        let text = try textEntry("Use #FF6A23 for the accent")
        let color = colorEntry("#FF6A23")

        XCTAssertFalse(HistorySearchMatcher.matches(text, query: "FF6A", scope: .colors))
        XCTAssertTrue(HistorySearchMatcher.matches(color, query: "ff6a", scope: .colors))
    }

    func testTextScopeExcludesMatchingColor() throws {
        let text = try textEntry("Theme color is #FF6A23")
        let color = colorEntry("#FF6A23")

        XCTAssertTrue(HistorySearchMatcher.matches(text, query: "theme", scope: .text))
        XCTAssertFalse(HistorySearchMatcher.matches(color, query: "FF6A", scope: .text))
    }

    func testEmptyQueryOnlyReportsEntriesSupportedByScope() throws {
        XCTAssertTrue(
            HistorySearchMatcher.matches(try textEntry("Anything"), query: "  ", scope: .text)
        )
        XCTAssertFalse(
            HistorySearchMatcher.matches(colorEntry("#123456"), query: "", scope: .text)
        )
    }

    private func textEntry(_ value: String) throws -> HistoryEntry {
        let url = directoryURL.appendingPathComponent("\(UUID().uuidString).txt")
        try value.write(to: url, atomically: true, encoding: .utf8)
        return HistoryEntry(
            fileURL: url,
            createdAt: Date(),
            kind: .text(HistoryTextContent(fileURL: url)),
            cloudURL: nil
        )
    }

    private func colorEntry(_ hex: String) -> HistoryEntry {
        HistoryEntry(
            fileURL: directoryURL.appendingPathComponent("\(UUID().uuidString).color"),
            createdAt: Date(),
            kind: .color(hex: hex),
            cloudURL: nil
        )
    }
}
