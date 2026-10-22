import AppKit
import Carbon
import XCTest
@testable import capcap

final class EditorShortcutRegistryTests: XCTestCase {
    func testLegacyEditorDefaultsRemainStable() {
        XCTAssertEqual(EditorShortcutAction.select.defaultBinding, binding(kVK_ANSI_V))
        XCTAssertEqual(EditorShortcutAction.shapeFill.defaultBinding, binding(kVK_ANSI_F))
        XCTAssertEqual(EditorShortcutAction.toolbar(.rectangle).defaultBinding, binding(kVK_ANSI_R))
        XCTAssertEqual(EditorShortcutAction.toolbar(.ellipse).defaultBinding, binding(kVK_ANSI_O))
        XCTAssertEqual(EditorShortcutAction.toolbar(.line).defaultBinding, binding(kVK_ANSI_L))
        XCTAssertEqual(EditorShortcutAction.toolbar(.arrow).defaultBinding, binding(kVK_ANSI_A))
        XCTAssertEqual(EditorShortcutAction.toolbar(.pen).defaultBinding, binding(kVK_ANSI_D))
        XCTAssertEqual(EditorShortcutAction.toolbar(.marker).defaultBinding, binding(kVK_ANSI_H))
        XCTAssertEqual(EditorShortcutAction.toolbar(.mosaic).defaultBinding, binding(kVK_ANSI_M))
        XCTAssertEqual(EditorShortcutAction.toolbar(.eraser).defaultBinding, binding(kVK_ANSI_E))
        XCTAssertEqual(EditorShortcutAction.toolbar(.numbered).defaultBinding, binding(kVK_ANSI_N))
        XCTAssertEqual(EditorShortcutAction.toolbar(.text).defaultBinding, binding(kVK_ANSI_T))
        XCTAssertEqual(EditorShortcutAction.toolbar(.pin).defaultBinding, binding(kVK_ANSI_P))
        XCTAssertEqual(EditorShortcutAction.toolbar(.close).defaultBinding, binding(kVK_ANSI_X))
        XCTAssertEqual(
            EditorShortcutAction.toolbar(.undo).defaultBinding,
            binding(kVK_ANSI_Z, modifiers: UInt32(cmdKey))
        )
        XCTAssertEqual(EditorShortcutAction.toolbar(.redo).defaultBinding, binding(kVK_ANSI_Z))
    }

    func testEveryToolbarItemExceptMoveSelectionHasAConfigurableAction() {
        let toolbarActions = Set(EditorShortcutAction.allCases.compactMap { action -> ToolbarItemID? in
            guard case .toolbar(let item) = action else { return nil }
            return item
        })
        XCTAssertEqual(toolbarActions, Set(ToolbarLayout.canonicalOrder.filter { $0 != .moveSelection }))
    }

    func testConfigurationSupportsCustomDisableAndRestoreWithoutLosingDefaults() {
        let action = EditorShortcutAction.toolbar(.rectangle)
        let custom = binding(kVK_ANSI_1)
        var configuration = EditorShortcutConfiguration()

        XCTAssertEqual(configuration.binding(for: action), binding(kVK_ANSI_R))

        configuration.setBinding(custom, for: action)
        XCTAssertEqual(configuration.binding(for: action), custom)
        XCTAssertTrue(configuration.hasOverride(for: action))

        configuration.disable(action)
        XCTAssertNil(configuration.binding(for: action))
        XCTAssertTrue(configuration.hasOverride(for: action))

        configuration.restoreDefault(for: action)
        XCTAssertEqual(configuration.binding(for: action), binding(kVK_ANSI_R))
        XCTAssertFalse(configuration.hasOverride(for: action))
    }

    func testDisabledOverrideSurvivesCodableRoundTrip() throws {
        let action = EditorShortcutAction.toolbar(.pin)
        var configuration = EditorShortcutConfiguration()
        configuration.disable(action)

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(EditorShortcutConfiguration.self, from: data)

        XCTAssertNil(decoded.binding(for: action))
        XCTAssertTrue(decoded.hasOverride(for: action))
    }

    func testBareBindingPreservesLegacyShiftVariantButRejectsCommand() throws {
        let shortcut = binding(kVK_ANSI_R)
        XCTAssertTrue(shortcut.matches(try keyEvent(keyCode: kVK_ANSI_R, modifiers: [])))
        XCTAssertTrue(shortcut.matches(try keyEvent(keyCode: kVK_ANSI_R, modifiers: .shift)))
        XCTAssertFalse(shortcut.matches(try keyEvent(keyCode: kVK_ANSI_R, modifiers: .command)))
    }

    func testBareAndShiftBindingsConflict() {
        let bare = binding(kVK_ANSI_R)
        let shifted = binding(kVK_ANSI_R, modifiers: UInt32(shiftKey))
        let commanded = binding(kVK_ANSI_R, modifiers: UInt32(cmdKey))

        XCTAssertTrue(bare.conflicts(with: shifted))
        XCTAssertFalse(bare.conflicts(with: commanded))
    }

    func testBindingDisplayUsesSharedHotkeyFormatting() {
        XCTAssertEqual(
            binding(kVK_F3, modifiers: UInt32(cmdKey | shiftKey)).displayString,
            "⇧⌘F3"
        )
        XCTAssertEqual(binding(kVK_Return).displayString, "Return")
    }

    private func binding(_ keyCode: Int, modifiers: UInt32 = 0) -> EditorShortcutBinding {
        EditorShortcutBinding(keyCode: UInt32(keyCode), modifiers: modifiers)
    }

    private func keyEvent(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "r",
                charactersIgnoringModifiers: "r",
                isARepeat: false,
                keyCode: UInt16(keyCode)
            )
        )
    }
}
