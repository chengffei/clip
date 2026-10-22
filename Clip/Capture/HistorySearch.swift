import Foundation

enum HistorySearchScope: Equatable {
    case colorsAndText
    case colors
    case text
    case files
}

enum HistorySearchMatcher {
    static func matches(_ entry: HistoryEntry, query: String, scope: HistorySearchScope) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return supports(entry, scope: scope)
        }

        switch entry.kind {
        case .color(let hex):
            guard scope == .colorsAndText || scope == .colors else { return false }
            return contains(hex, needle: needle)
        case .text(let content):
            guard scope == .colorsAndText || scope == .text else { return false }
            return contains(content.value, needle: needle)
        case .files(let files):
            guard scope == .colorsAndText || scope == .files else { return false }
            return contains(files.searchText, needle: needle)
        case .image, .video:
            return false
        }
    }

    private static func supports(_ entry: HistoryEntry, scope: HistorySearchScope) -> Bool {
        switch entry.kind {
        case .color:
            return scope == .colorsAndText || scope == .colors
        case .text:
            return scope == .colorsAndText || scope == .text
        case .files:
            return scope == .colorsAndText || scope == .files
        case .image, .video:
            return false
        }
    }

    private static func contains(_ candidate: String, needle: String) -> Bool {
        candidate.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        ) != nil
    }
}
