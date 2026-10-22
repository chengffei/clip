import Foundation
import XCTest
@testable import capcap

/// Frozen oracle for per-item history favorites
/// Expected values are stated from the spec, independent of the implementation.
final class HistoryFavoriteTests: XCTestCase {
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

    // E1 — favoriting a writable file persists to disk and is readable back.
    func testSetFavoritePersists() throws {
        let f = try makeFile(name: "image.png", contents: Data([0x01]))

        XCTAssertTrue(HistoryManager.setFavorite(true, on: f))
        XCTAssertTrue(HistoryManager.isFavorite(url: f))

        // A freshly constructed URL over the same path must also observe the attribute.
        let freshURL = URL(fileURLWithPath: f.path)
        XCTAssertTrue(HistoryManager.isFavorite(url: freshURL))

        // Shell cross-check: the OS `xattr` tool reads the same attribute over a
        // different code path than capcap's getxattr, and must print "1".
        XCTAssertEqual(try shellFavoriteXattrValue(of: f), "1")
    }

    // E2 — a write to a path that cannot exist reports failure, never success.
    func testSetFavoriteFailsForUnwritablePath() throws {
        let missing = URL(fileURLWithPath: "/nonexistent-capcap-dir-4f2a/x.png")

        XCTAssertFalse(HistoryManager.setFavorite(true, on: missing))
        XCTAssertFalse(HistoryManager.isFavorite(url: missing))
    }

    // E3 — unfavoriting a file that was never favorited is already the requested
    // state, so it counts as success (ENOATTR is not a failure here).
    func testSetFavoriteFalseWhenAlreadyUnfavoritedIsSuccess() throws {
        let f = try makeFile(name: "plain.png", contents: Data([0x02]))

        XCTAssertTrue(HistoryManager.setFavorite(false, on: f))
        XCTAssertFalse(HistoryManager.isFavorite(url: f))
    }

    // R6 — favorite round trip on one file. Exercises the removexattr-success
    // path (unfavoriting a file that IS favorited), which the ENOATTR edge in E3 does
    // not, and proves the attribute round-trips rather than sticking.
    func testSetFavoriteRoundTripOnSameFile() throws {
        let f = try makeFile(name: "round-trip.png", contents: Data([0x01]))

        XCTAssertTrue(HistoryManager.setFavorite(true, on: f))
        XCTAssertTrue(HistoryManager.isFavorite(url: f))

        XCTAssertTrue(HistoryManager.setFavorite(false, on: f))
        XCTAssertFalse(HistoryManager.isFavorite(url: f))

        // Re-favoriting proves the state is not sticky and the attribute round-trips.
        XCTAssertTrue(HistoryManager.setFavorite(true, on: f))
        XCTAssertTrue(HistoryManager.isFavorite(url: f))
    }

    // E4 — "delete all history" keeps favorite entries and reports how many it kept.
    func testClearAllKeepsFavoriteEntries() throws {
        let favorite = try makeFile(name: "favorite.png", contents: Data([0x01]))
        let plain = try makeFile(name: "plain.png", contents: Data([0x02]))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: favorite))

        let candidates = [favorite, plain]
        let decision = HistoryManager.partitionEntriesForRemoval(candidates)

        XCTAssertEqual(decision.kept, [favorite])
        XCTAssertEqual(decision.remove, [plain])

        // Performing the removal the way production does leaves the favorite file on disk.
        for url in decision.remove {
            try? FileManager.default.removeItem(at: url)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: favorite.path))
    }

    func testSelectedDeletionKeepsFavoritesAndDeletesOtherSelectedEntries() throws {
        let favorite = try makeFile(name: "favorite.png", contents: Data([0x01]))
        let plain = try makeFile(name: "plain.png", contents: Data([0x02]))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: favorite))

        let result = HistoryManager.removeUnfavoritedEntries([favorite, plain])

        XCTAssertEqual(result.removed, [plain])
        XCTAssertEqual(result.kept, [favorite])
        XCTAssertTrue(FileManager.default.fileExists(atPath: favorite.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path))
    }

    func testDeletionToastReportsDeletedAndSkippedCounts() {
        let previousLanguage = Defaults.language
        Defaults.language = .zh
        defer { Defaults.language = previousLanguage }

        XCTAssertEqual(L10n.historyDeletedSkippingFavorites(removed: 1, skipped: 2),
                       "已删除 1 个项目，跳过 2 个收藏")
        XCTAssertEqual(L10n.historyDeletedSkippingFavorites(removed: 0, skipped: 2),
                       "已删除 0 个项目，跳过 2 个收藏")
    }

    func testCacheDisablingKeepsFavoritesOfEachType() throws {
        let favoriteImage = try makeFile(name: "favorite.png", contents: Data([0x01]))
        let plainImage = try makeFile(name: "plain.png", contents: Data([0x02]))
        let favoriteText = try makeFile(name: "favorite.txt", contents: Data("saved".utf8))
        let plainText = try makeFile(name: "plain.txt", contents: Data("temporary".utf8))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: favoriteImage))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: favoriteText))

        let candidates = [favoriteImage, plainImage, favoriteText, plainText]
        let mediaResult = HistoryManager.removeStoredHistoryEntries(
            candidates, withExtensions: ["png", "gif", "mp4", "color"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: plainText.path),
                      "disabling media cache must not clear text history")
        let textResult = HistoryManager.removeStoredHistoryEntries(
            candidates, withExtensions: ["txt"])

        XCTAssertEqual(mediaResult.removed, [plainImage])
        XCTAssertEqual(textResult.removed, [plainText])
        XCTAssertEqual(mediaResult.kept, [favoriteImage])
        XCTAssertEqual(textResult.kept, [favoriteText])
        XCTAssertTrue(FileManager.default.fileExists(atPath: favoriteImage.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: favoriteText.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plainImage.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plainText.path))
    }

    func testFavoritesRemainVisibleWhenTheirCacheIsDisabled() throws {
        let favoriteImage = try makeFile(name: "favorite.png", contents: Data([0x01]))
        let plainImage = try makeFile(name: "plain.png", contents: Data([0x02]))
        let favoriteText = try makeFile(name: "favorite.txt", contents: Data("saved".utf8))
        let unsupported = try makeFile(name: "favorite.pdf", contents: Data([0x03]))
        for url in [favoriteImage, favoriteText, unsupported] {
            XCTAssertTrue(HistoryManager.setFavorite(true, on: url))
        }

        let supported: Set<String> = ["png", "txt"]
        XCTAssertTrue(HistoryManager.shouldIncludeEntry(favoriteImage,
                                                        allowedExtensions: [],
                                                        supportedExtensions: supported))
        XCTAssertTrue(HistoryManager.shouldIncludeEntry(favoriteText,
                                                        allowedExtensions: [],
                                                        supportedExtensions: supported))
        XCTAssertFalse(HistoryManager.shouldIncludeEntry(plainImage,
                                                         allowedExtensions: [],
                                                         supportedExtensions: supported))
        XCTAssertFalse(HistoryManager.shouldIncludeEntry(unsupported,
                                                         allowedExtensions: [],
                                                         supportedExtensions: supported))
    }

    func testFavoriteFilterIsSecondAfterAll() {
        XCTAssertEqual(Array(HistoryPanelFilter.allCases.prefix(2)), [.all, .favorites])
    }

    func testFavoriteFilterAppearsWhenAtLeastOneEntryIsFavorite() throws {
        let first = try makeEntry(name: "first.png")
        let second = try makeEntry(name: "second.png")
        let entries = [first, second]

        XCTAssertFalse(HistoryFavoritePolicy.shouldShowFilter(for: entries))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: first.fileURL))
        XCTAssertTrue(HistoryFavoritePolicy.shouldShowFilter(for: entries))
        XCTAssertTrue(HistoryManager.setFavorite(true, on: second.fileURL))
        XCTAssertTrue(HistoryFavoritePolicy.shouldShowFilter(for: entries))
    }

    func testMultiSelectionTargetsAllSelectedEntries() throws {
        let first = try makeEntry(name: "first.png")
        let second = try makeEntry(name: "second.png")
        let clicked = try makeEntry(name: "clicked.png")

        let targets = HistoryFavoritePolicy.toggleTargets(
            clicked: clicked,
            selected: [first, second]
        )

        XCTAssertEqual(targets.map(\.fileURL), [first.fileURL, second.fileURL])
    }

    func testMixedSelectionFavoritesAllBeforeBatchUnfavoriting() throws {
        let first = try makeEntry(name: "first.png")
        let second = try makeEntry(name: "second.png")
        let entries = [first, second]

        XCTAssertTrue(HistoryManager.setFavorite(true, on: first.fileURL))
        XCTAssertTrue(HistoryFavoritePolicy.nextFavoriteState(for: entries))

        XCTAssertTrue(HistoryManager.setFavorite(true, on: second.fileURL))
        XCTAssertFalse(HistoryFavoritePolicy.nextFavoriteState(for: entries))
    }

    func testFavoriteButtonUsesOutlineAndFilledStarSymbols() {
        XCTAssertEqual(HistoryFavoriteButton.symbolName(isFavorite: false), "star")
        XCTAssertEqual(HistoryFavoriteButton.symbolName(isFavorite: true), "star.fill")
        XCTAssertEqual(HistoryItemCornerControlMetrics.size, 18)
        XCTAssertEqual(HistoryItemCornerControlMetrics.favoriteSymbolPointSize, 14)
        XCTAssertEqual(HistoryItemCornerControlMetrics.horizontalPreviewOverlap, 5)
        XCTAssertEqual(HistoryItemCornerControlMetrics.favoritePreviewOverlap, 7)
    }

    func testFavoriteButtonAppearsOnHoverAndStaysVisibleWhenFavorite() {
        XCTAssertFalse(HistoryFavoriteButton.shouldBeVisible(isFavorite: false, isHovered: false))
        XCTAssertTrue(HistoryFavoriteButton.shouldBeVisible(isFavorite: false, isHovered: true))
        XCTAssertTrue(HistoryFavoriteButton.shouldBeVisible(isFavorite: true, isHovered: false))
    }

    private func makeEntry(name: String) throws -> HistoryEntry {
        let url = try makeFile(name: name, contents: Data([0x01]))
        return HistoryEntry(fileURL: url, createdAt: Date(), kind: .image, cloudURL: nil)
    }

    @discardableResult
    private func makeFile(name: String, contents: Data) throws -> URL {
        let url = directoryURL.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    /// Runs `/usr/bin/xattr -p com.capcap.favorite <path>` and returns its stdout,
    /// reading the attribute through the OS tool rather than capcap's getxattr.
    private func shellFavoriteXattrValue(of url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-p", "com.capcap.favorite", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
