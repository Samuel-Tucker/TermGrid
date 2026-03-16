import Foundation

enum MessageParser {
    static func extractSummary(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let pattern = #"[^.!?]*[.!?]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return trimmed
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, range: range)

        guard !matches.isEmpty else {
            return trimmed
        }

        for match in matches.reversed() {
            if let swiftRange = Range(match.range, in: trimmed) {
                let sentence = String(trimmed[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if sentence.hasSuffix("?") {
                    return sentence
                }
            }
        }

        if let lastMatch = matches.last,
           let swiftRange = Range(lastMatch.range, in: trimmed) {
            return String(trimmed[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }
}
