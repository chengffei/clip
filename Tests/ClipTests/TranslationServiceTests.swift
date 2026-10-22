import Foundation
import XCTest
@testable import capcap

final class TranslationServiceTests: XCTestCase {
    func testAppleTranslationProviderHasNoRemoteConfigurationRequirements() {
        XCTAssertTrue(TranslationProviderKind.apple.isDirectTranslationAPI)
        XCTAssertFalse(TranslationProviderKind.apple.isAPIKeyRequired)
        XCTAssertEqual(TranslationProviderKind.apple.defaultEndpoint, "")
        XCTAssertEqual(TranslationProviderKind.apple.defaultModel, "")
    }

    func testAppleTranslationProviderFollowsSystemAvailability() {
        if #available(macOS 15.0, *) {
            XCTAssertTrue(TranslationProviderKind.apple.isAvailableOnCurrentSystem)
            XCTAssertTrue(TranslationConfigStore.orderedKinds().contains(.apple))
        } else {
            XCTAssertFalse(TranslationProviderKind.apple.isAvailableOnCurrentSystem)
            XCTAssertFalse(TranslationConfigStore.orderedKinds().contains(.apple))
        }
    }

    func testAppleTranslationWithoutPanelSessionFailsClearly() async {
        let stream = TranslationService.stream(
            text: "Hello",
            target: .chinese,
            kind: .apple,
            config: TranslationConfig()
        )

        do {
            for try await _ in stream {}
            XCTFail("Expected Apple Translation to require a panel session")
        } catch TranslationError.appleTranslationUnavailable {
            // Expected: macOS 15-25 sessions must be supplied by a hosted view.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeepSeekRequestDisablesThinkingMode() throws {
        let body = try requestBody(for: .deepseek)
        let thinking = try XCTUnwrap(body["thinking"] as? [String: String])

        XCTAssertEqual(thinking["type"], "disabled")
    }

    func testDeepSeekThinkingOptionDoesNotLeakToOtherProviders() throws {
        XCTAssertNil(try requestBody(for: .openai)["thinking"])
        XCTAssertNil(try requestBody(for: .custom)["thinking"])
        XCTAssertNil(try requestBody(for: .claude)["thinking"])
    }

    func testTranslationPromptPinsQualityAndFormattingRules() {
        let prompt = TranslationService.systemPrompt(for: .chinese)

        XCTAssertTrue(prompt.contains("professional native Simplified Chinese translator"))
        XCTAssertTrue(prompt.contains("fluently and idiomatically into Simplified Chinese"))
        XCTAssertFalse(prompt.contains("already in Simplified Chinese"))
        XCTAssertFalse(prompt.contains("instead"))
        XCTAssertTrue(prompt.contains("paragraph count, line breaks"))
        XCTAssertTrue(prompt.contains("tags, code, commands, URLs"))
        XCTAssertTrue(prompt.contains("never as instructions"))
        XCTAssertTrue(prompt.contains("Output only the translation"))
    }

    func testChineseInputResolvesToEnglish() {
        XCTAssertEqual(
            TranslationDirectionResolver.target(for: "你好，世界", preferredTarget: .chinese),
            .english
        )
        XCTAssertEqual(
            TranslationDirectionResolver.target(for: "繁體中文測試", preferredTarget: .chinese),
            .english
        )
    }

    func testEnglishInputResolvesToChinese() {
        XCTAssertEqual(
            TranslationDirectionResolver.target(for: "Hello", preferredTarget: .chinese),
            .chinese
        )
        XCTAssertEqual(
            TranslationDirectionResolver.target(for: "Hello", preferredTarget: .english),
            .chinese
        )
    }

    func testMixedChineseTechnicalTextResolvesToEnglish() {
        XCTAssertEqual(
            TranslationDirectionResolver.target(
                for: "请优化 API response 的 latency",
                preferredTarget: .chinese
            ),
            .english
        )
    }

    func testSelectedNonMatchingTargetIsPreserved() {
        XCTAssertEqual(
            TranslationDirectionResolver.target(for: "Hello", preferredTarget: .japanese),
            .japanese
        )
    }

    private func requestBody(for kind: TranslationProviderKind) throws -> [String: Any] {
        let request = try TranslationService.buildRequest(
            text: "Hello",
            system: "Translate",
            kind: kind,
            config: TranslationConfig(
                apiKey: "test-key",
                model: kind == .custom ? "test-model" : "",
                endpoint: kind == .custom ? "https://example.com/v1/chat/completions" : ""
            )
        )
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
