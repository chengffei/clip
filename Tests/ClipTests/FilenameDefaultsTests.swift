import XCTest
@testable import Clip

final class FilenameDefaultsTests: XCTestCase {
    func testDefaultsUseClipPrefixAndCustomTemplatesAreKept() {
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: "imageFilenameTemplate"), defaults.object(forKey: "recordingFilenameTemplate"))
        defer {
            defaults.set(saved.0, forKey: "imageFilenameTemplate")
            defaults.set(saved.1, forKey: "recordingFilenameTemplate")
        }
        defaults.removeObject(forKey: "imageFilenameTemplate")
        XCTAssertEqual(Defaults.imageFilenameTemplate, "clip-{date}-{time}")
        defaults.set("mine-{date}", forKey: "imageFilenameTemplate")
        XCTAssertEqual(Defaults.imageFilenameTemplate, "mine-{date}", "custom templates are kept")
    }
}
