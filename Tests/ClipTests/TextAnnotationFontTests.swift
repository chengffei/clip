import AppKit
import XCTest
@testable import capcap

@MainActor
final class TextAnnotationFontTests: XCTestCase {

    /// A family that is guaranteed to exist on every macOS install we target.
    private var installedFamily: String {
        let families = FontCatalog.families
        return families.first(where: { $0 == "Helvetica" })
            ?? families.first(where: { $0 == "Menlo" })
            ?? families[0]
    }

    // MARK: - Font resolution

    func testNilFontNameResolvesToSystemBold() {
        let resolved = TextAnnotation.font(named: nil, size: 24)
        XCTAssertEqual(resolved, NSFont.systemFont(ofSize: 24, weight: .bold))
        XCTAssertEqual(TextAnnotation.font(forSize: 24), resolved)
    }

    func testEmptyFontNameResolvesToSystemBold() {
        XCTAssertEqual(
            TextAnnotation.font(named: "", size: 18),
            NSFont.systemFont(ofSize: 18, weight: .bold)
        )
    }

    func testUnknownFontFamilyFallsBackToSystemBold() {
        XCTAssertEqual(
            TextAnnotation.font(named: "capcap No Such Family 12345", size: 20),
            NSFont.systemFont(ofSize: 20, weight: .bold)
        )
    }

    func testInstalledFontFamilyResolvesToThatFamily() throws {
        let family = installedFamily
        let resolved = TextAnnotation.font(named: family, size: 22)
        XCTAssertEqual(resolved.pointSize, 22)
        XCTAssertEqual(resolved.familyName, family)
        XCTAssertNotEqual(resolved, NSFont.systemFont(ofSize: 22, weight: .bold))
    }

    func testResolvedFontFollowsAnnotationFontName() {
        let family = installedFamily
        let annotation = TextAnnotation(
            text: "hello",
            origin: NSPoint(x: 10, y: 10),
            color: .red,
            fontSize: 16,
            fontName: family
        )
        XCTAssertEqual(annotation.resolvedFont.familyName, family)
        XCTAssertEqual(annotation.resolvedFont.pointSize, 16)
    }

    // MARK: - Value-type transforms

    func testWithFontNamePreservesEveryOtherField() {
        let family = installedFamily
        let original = TextAnnotation(
            text: "line one\nline two",
            origin: NSPoint(x: 40, y: 80),
            color: .systemBlue,
            fontSize: 30,
            rotation: 0.4,
            hasStroke: true,
            hasCallout: true,
            calloutTip: NSPoint(x: 120, y: 30),
            secondCalloutTip: NSPoint(x: 10, y: 60)
        )

        let changed = original.withFontName(family)

        XCTAssertEqual(changed.fontName, family)
        XCTAssertEqual(changed.text, original.text)
        XCTAssertEqual(changed.color, original.color)
        XCTAssertEqual(changed.fontSize, original.fontSize)
        XCTAssertEqual(changed.rotation, original.rotation)
        XCTAssertEqual(changed.hasStroke, original.hasStroke)
        XCTAssertEqual(changed.hasCallout, original.hasCallout)
        XCTAssertEqual(changed.calloutTip, original.calloutTip)
        XCTAssertEqual(changed.secondCalloutTip, original.secondCalloutTip)
        // The cap line stays anchored, so x never moves and y only absorbs the
        // line-height delta between the two faces.
        XCTAssertEqual(changed.origin.x, original.origin.x)
    }

    func testWithFontNameIsReversible() {
        let family = installedFamily
        let original = TextAnnotation(
            text: "round trip",
            origin: NSPoint(x: 5, y: 5),
            color: .white,
            fontSize: 18
        )
        let restored = original.withFontName(family).withFontName(nil)
        XCTAssertNil(restored.fontName)
        XCTAssertEqual(restored.origin.y, original.origin.y, accuracy: 0.001)
    }

    func testWithFontSizeKeepsFontName() throws {
        let family = installedFamily
        let original = TextAnnotation(
            text: "resize",
            origin: .zero,
            color: .white,
            fontSize: 18,
            fontName: family
        )
        let resized = try XCTUnwrap(original.withFontSize(36) as? TextAnnotation)
        XCTAssertEqual(resized.fontName, family)
        XCTAssertEqual(resized.fontSize, 36)
    }

    // MARK: - Defaults normalization

    func testDefaultTextFontNormalizesUninstalledFamily() {
        let previous = Defaults.textFontName
        defer { Defaults.textFontName = previous }

        Defaults.textFontName = installedFamily
        XCTAssertEqual(Defaults.textFontName, installedFamily)

        UserDefaults.standard.set("capcap No Such Family 12345", forKey: "textFontName")
        XCTAssertNil(Defaults.textFontName, "An uninstalled family must read back as the system default")

        Defaults.textFontName = nil
        XCTAssertNil(Defaults.textFontName)

        Defaults.textFontName = ""
        XCTAssertNil(Defaults.textFontName)
    }

    // MARK: - Catalog

    func testFontCatalogHidesDotPrefixedSystemFaces() {
        XCTAssertFalse(FontCatalog.families.isEmpty)
        XCTAssertFalse(FontCatalog.families.contains { $0.hasPrefix(".") })
    }

    func testFontCatalogTitleFallsBackToSystemDefaultLabel() {
        XCTAssertEqual(FontCatalog.title(for: nil), L10n.textFontSystemDefault)
        XCTAssertEqual(
            FontCatalog.title(for: "capcap No Such Family 12345"),
            L10n.textFontSystemDefault
        )
        XCTAssertEqual(
            FontCatalog.title(for: installedFamily),
            FontCatalog.displayName(for: installedFamily)
        )
    }
}
