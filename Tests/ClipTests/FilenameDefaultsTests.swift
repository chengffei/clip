import XCTest
@testable import Clip

final class FilenameDefaultsTests: XCTestCase {
    func testDefaultsUseClipPrefixAndLegacyPresetsMigrate() {
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: "imageFilenameTemplate"), defaults.object(forKey: "recordingFilenameTemplate"))
        defer {
            defaults.set(saved.0, forKey: "imageFilenameTemplate")
            defaults.set(saved.1, forKey: "recordingFilenameTemplate")
        }
        defaults.removeObject(forKey: "imageFilenameTemplate")
        XCTAssertEqual(Defaults.imageFilenameTemplate, "clip-{date}-{time}")
        defaults.set("capcap-{date}-{time}-{rand:3}", forKey: "imageFilenameTemplate")
        XCTAssertEqual(Defaults.imageFilenameTemplate, "clip-{date}-{time}-{rand:3}")
        defaults.set("capcap-rec-{date}-{daily:3}", forKey: "recordingFilenameTemplate")
        XCTAssertEqual(Defaults.recordingFilenameTemplate, "clip-rec-{date}-{daily:3}")
        defaults.set("capcap-mine-{date}", forKey: "imageFilenameTemplate")
        XCTAssertEqual(Defaults.imageFilenameTemplate, "capcap-mine-{date}", "custom templates are kept")
    }
}
