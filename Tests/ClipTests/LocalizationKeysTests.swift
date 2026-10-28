import XCTest

/// Every key the app looks up must exist in both string tables, so pruning
/// unused keys can never drop one that is still shown.
final class LocalizationKeysTests: XCTestCase {
    func testEveryLookedUpKeyExistsInBothLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let defaults = try String(contentsOf: root.appendingPathComponent("Clip/Utilities/Defaults.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\bs\("([A-Za-z0-9_.]+)"\)"#)
        let keys = Set(regex.matches(in: defaults, range: NSRange(defaults.startIndex..., in: defaults)).compactMap {
            Range($0.range(at: 1), in: defaults).map { String(defaults[$0]) }
        })
        XCTAssertGreaterThan(keys.count, 100)
        for lang in ["zh-Hans", "en"] {
            let url = root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            let missing = keys.subtracting(table.keys).sorted()
            XCTAssertEqual(missing, [], "\(lang) is missing \(missing)")
        }
    }
}
