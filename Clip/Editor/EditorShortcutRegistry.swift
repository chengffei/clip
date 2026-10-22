import AppKit
import Carbon

struct EditorShortcutBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: HotkeyManager.carbonModifiers(from: event.modifierFlags)
        )
    }

    var displayString: String {
        HotkeyManager.modifierString(modifiers) + HotkeyManager.keyString(keyCode)
    }

    func matches(_ event: NSEvent) -> Bool {
        guard UInt32(event.keyCode) == keyCode else { return false }
        let eventModifiers = HotkeyManager.carbonModifiers(from: event.modifierFlags)
        if modifiers == 0 {
            // Legacy editor shortcuts accepted Shift together with their bare
            // mnemonic key. Preserve that behavior for existing muscle memory.
            return eventModifiers == 0 || eventModifiers == UInt32(shiftKey)
        }
        return eventModifiers == modifiers
    }

    func conflicts(with other: EditorShortcutBinding) -> Bool {
        guard keyCode == other.keyCode else { return false }
        if modifiers == other.modifiers { return true }
        let bareAndShift = Set([UInt32(0), UInt32(shiftKey)])
        return bareAndShift.contains(modifiers) && bareAndShift.contains(other.modifiers)
    }
}

enum EditorShortcutAction: Hashable {
    case select
    case shapeFill
    case toolbar(ToolbarItemID)

    static let allCases: [EditorShortcutAction] = [
        .select,
        .shapeFill,
    ] + ToolbarLayout.canonicalOrder
        .filter(\.supportsEditorShortcut)
        .map(EditorShortcutAction.toolbar)

    var persistenceKey: String {
        switch self {
        case .select: return "select"
        case .shapeFill: return "shapeFill"
        case .toolbar(let item): return "toolbar.\(item.rawValue)"
        }
    }

    var localizedTitle: String {
        switch self {
        case .select: return L10n.editorShortcutSelect
        case .shapeFill: return L10n.editorShortcutShapeFill
        case .toolbar(let item): return item.localizedTitle
        }
    }

    var defaultBinding: EditorShortcutBinding? {
        let keyCode: Int?
        let modifiers: UInt32
        switch self {
        case .select:
            keyCode = kVK_ANSI_V
            modifiers = 0
        case .shapeFill:
            keyCode = kVK_ANSI_F
            modifiers = 0
        case .toolbar(.rectangle):
            keyCode = kVK_ANSI_R
            modifiers = 0
        case .toolbar(.ellipse):
            keyCode = kVK_ANSI_O
            modifiers = 0
        case .toolbar(.line):
            keyCode = kVK_ANSI_L
            modifiers = 0
        case .toolbar(.arrow):
            keyCode = kVK_ANSI_A
            modifiers = 0
        case .toolbar(.pen):
            keyCode = kVK_ANSI_D
            modifiers = 0
        case .toolbar(.marker):
            keyCode = kVK_ANSI_H
            modifiers = 0
        case .toolbar(.mosaic):
            keyCode = kVK_ANSI_M
            modifiers = 0
        case .toolbar(.eraser):
            keyCode = kVK_ANSI_E
            modifiers = 0
        case .toolbar(.numbered):
            keyCode = kVK_ANSI_N
            modifiers = 0
        case .toolbar(.text):
            keyCode = kVK_ANSI_T
            modifiers = 0
        case .toolbar(.undo):
            keyCode = kVK_ANSI_Z
            modifiers = UInt32(cmdKey)
        case .toolbar(.redo):
            keyCode = kVK_ANSI_Z
            modifiers = 0
        case .toolbar(.pin):
            keyCode = kVK_ANSI_P
            modifiers = 0
        case .toolbar(.close):
            keyCode = kVK_ANSI_X
            modifiers = 0
        case .toolbar(.save), .toolbar(.confirm), .toolbar(.moveSelection):
            return nil
        case .toolbar:
            return nil
        }
        return keyCode.map { EditorShortcutBinding(keyCode: UInt32($0), modifiers: modifiers) }
    }
}

private struct EditorShortcutOverride: Codable, Equatable {
    /// `nil` means the user explicitly disabled the default binding.
    let binding: EditorShortcutBinding?
}

struct EditorShortcutConfiguration: Codable, Equatable {
    fileprivate var overrides: [String: EditorShortcutOverride] = [:]

    func binding(for action: EditorShortcutAction) -> EditorShortcutBinding? {
        if let override = overrides[action.persistenceKey] {
            return override.binding
        }
        return action.defaultBinding
    }

    func hasOverride(for action: EditorShortcutAction) -> Bool {
        overrides[action.persistenceKey] != nil
    }

    mutating func setBinding(_ binding: EditorShortcutBinding, for action: EditorShortcutAction) {
        overrides[action.persistenceKey] = EditorShortcutOverride(binding: binding)
    }

    mutating func disable(_ action: EditorShortcutAction) {
        overrides[action.persistenceKey] = EditorShortcutOverride(binding: nil)
    }

    mutating func restoreDefault(for action: EditorShortcutAction) {
        overrides.removeValue(forKey: action.persistenceKey)
    }
}

enum EditorShortcutRegistry {
    private static let separatelyHandledToolbarItems: Set<ToolbarItemID> = [
        .undo, .redo, .save, .confirm,
    ]

    static func binding(for action: EditorShortcutAction) -> EditorShortcutBinding? {
        switch action {
        case .toolbar(.save):
            let hotkey = HotkeyManager.shared.currentFileSaveHotkey()
            return EditorShortcutBinding(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers)
        case .toolbar(.confirm):
            guard let hotkey = HotkeyManager.shared.currentClipboardHotkey() else { return nil }
            return EditorShortcutBinding(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers)
        default:
            return Defaults.editorShortcutConfiguration.binding(for: action)
        }
    }

    static func displayString(for action: EditorShortcutAction) -> String? {
        if action == .toolbar(.confirm), binding(for: action) == nil {
            return L10n.clipboardShortcutDefaultDisplay
        }
        return binding(for: action)?.displayString
    }

    static func action(matching event: NSEvent) -> EditorShortcutAction? {
        EditorShortcutAction.allCases.first { action in
            if case .toolbar(let item) = action,
               separatelyHandledToolbarItems.contains(item) {
                return false
            }
            return binding(for: action)?.matches(event) == true
        }
    }

    static func eventMatches(_ event: NSEvent, action: EditorShortcutAction) -> Bool {
        binding(for: action)?.matches(event) == true
    }

    static func hasOverride(for action: EditorShortcutAction) -> Bool {
        switch action {
        case .toolbar(.save):
            return Defaults.hasCustomFileSaveHotkey
        case .toolbar(.confirm):
            return Defaults.hasCustomClipboardHotkey
        default:
            return Defaults.editorShortcutConfiguration.hasOverride(for: action)
        }
    }

    static func canDisable(_ action: EditorShortcutAction) -> Bool {
        switch action {
        case .toolbar(.save), .toolbar(.confirm): return false
        default: return true
        }
    }

    static func setBinding(_ binding: EditorShortcutBinding, for action: EditorShortcutAction) {
        switch action {
        case .toolbar(.save):
            Defaults.fileSaveHotkeyKeyCode = Int(binding.keyCode)
            Defaults.fileSaveHotkeyModifiers = Int(binding.modifiers)
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        case .toolbar(.confirm):
            Defaults.clipboardHotkeyKeyCode = Int(binding.keyCode)
            Defaults.clipboardHotkeyModifiers = Int(binding.modifiers)
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        default:
            var configuration = Defaults.editorShortcutConfiguration
            configuration.setBinding(binding, for: action)
            Defaults.editorShortcutConfiguration = configuration
        }
        NotificationCenter.default.post(name: .editorShortcutsDidChange, object: nil)
    }

    static func disable(_ action: EditorShortcutAction) {
        guard canDisable(action) else { return }
        var configuration = Defaults.editorShortcutConfiguration
        configuration.disable(action)
        Defaults.editorShortcutConfiguration = configuration
        NotificationCenter.default.post(name: .editorShortcutsDidChange, object: nil)
    }

    static func restoreDefault(for action: EditorShortcutAction) {
        switch action {
        case .toolbar(.save):
            Defaults.clearFileSaveHotkey()
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        case .toolbar(.confirm):
            Defaults.clearClipboardHotkey()
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        default:
            var configuration = Defaults.editorShortcutConfiguration
            configuration.restoreDefault(for: action)
            Defaults.editorShortcutConfiguration = configuration
        }
        NotificationCenter.default.post(name: .editorShortcutsDidChange, object: nil)
    }

    static func restoreAllDefaults() {
        Defaults.editorShortcutConfiguration = EditorShortcutConfiguration()
        Defaults.clearFileSaveHotkey()
        Defaults.clearClipboardHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        NotificationCenter.default.post(name: .editorShortcutsDidChange, object: nil)
    }

    static func validationMessage(
        for binding: EditorShortcutBinding,
        assigningTo action: EditorShortcutAction
    ) -> String? {
        if isReserved(binding) {
            return L10n.editorShortcutReserved
        }

        if let conflict = EditorShortcutAction.allCases.first(where: { candidate in
            candidate != action && Self.binding(for: candidate)?.conflicts(with: binding) == true
        }) {
            return L10n.editorShortcutConflict(conflict.localizedTitle)
        }

        let slot: HotkeyManager.HotkeySlot?
        switch action {
        case .toolbar(.save): slot = .fileSave
        case .toolbar(.confirm): slot = .clipboard
        default: slot = nil
        }
        let externalBindings: [EditorShortcutBinding]
        if binding.modifiers == 0 {
            externalBindings = [
                binding,
                EditorShortcutBinding(keyCode: binding.keyCode, modifiers: UInt32(shiftKey)),
            ]
        } else {
            externalBindings = [binding]
        }

        for externalBinding in externalBindings {
            if let message = HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: externalBinding.keyCode,
                modifiers: externalBinding.modifiers,
                assigningTo: slot
            ) {
                return message
            }
        }
        return nil
    }

    private static func isReserved(_ binding: EditorShortcutBinding) -> Bool {
        if binding.keyCode == UInt32(kVK_Escape) { return true }
        let navigationKeys: Set<UInt32> = [
            UInt32(kVK_LeftArrow), UInt32(kVK_RightArrow),
            UInt32(kVK_UpArrow), UInt32(kVK_DownArrow),
            UInt32(kVK_Delete), UInt32(kVK_ForwardDelete),
        ]
        if navigationKeys.contains(binding.keyCode) { return true }

        let commandOnly = binding.modifiers == UInt32(cmdKey)
        let annotationClipboardKeys: Set<UInt32> = [
            UInt32(kVK_ANSI_A), UInt32(kVK_ANSI_C),
            UInt32(kVK_ANSI_V), UInt32(kVK_ANSI_X),
        ]
        return commandOnly && annotationClipboardKeys.contains(binding.keyCode)
    }
}

extension Defaults {
    private static let editorShortcutConfigurationKey = "editor.shortcutConfiguration.v1"

    static var editorShortcutConfiguration: EditorShortcutConfiguration {
        get {
            guard let data = UserDefaults.standard.data(forKey: editorShortcutConfigurationKey),
                  let configuration = try? JSONDecoder().decode(EditorShortcutConfiguration.self, from: data)
            else {
                return EditorShortcutConfiguration()
            }
            return configuration
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: editorShortcutConfigurationKey)
        }
    }
}

extension ToolbarItemID {
    var supportsEditorShortcut: Bool {
        self != .moveSelection
    }
}
