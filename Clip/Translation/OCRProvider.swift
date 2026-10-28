import Foundation

struct OCRResult {
    let text: String
    let lines: [RecognizedTextLine]

    init(text: String? = nil, lines: [RecognizedTextLine] = []) {
        self.text = (text ?? lines.map(\.text).joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.lines = lines
    }
}
