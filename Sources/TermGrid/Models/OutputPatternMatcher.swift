import Foundation

enum NotificationSeverity {
    case success, error, attention
}

struct PatternMatch {
    let severity: NotificationSeverity
    let pattern: String
    let line: String
}

struct OutputPatternMatcher {
    private var lineBuffer: [UInt8] = []

    private static let patterns: [(regex: String, severity: NotificationSeverity)] = [
        ("Build complete!", .success),
        ("Test run with .* passed", .success),
        ("^error:", .error),
        ("^FAIL", .error),
    ]

    mutating func processChunk(_ bytes: [UInt8]) -> [PatternMatch] {
        var matches: [PatternMatch] = []
        lineBuffer.append(contentsOf: bytes)

        while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
            let lineBytes = Array(lineBuffer[lineBuffer.startIndex...newlineIndex])
            lineBuffer.removeFirst(lineBytes.count)

            guard let rawLine = String(bytes: lineBytes, encoding: .utf8) else { continue }
            let cleanLine = Self.stripAnsi(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanLine.isEmpty else { continue }

            for (pattern, severity) in Self.patterns {
                if let _ = cleanLine.range(of: pattern, options: .regularExpression) {
                    matches.append(PatternMatch(severity: severity, pattern: pattern, line: cleanLine))
                    break
                }
            }
        }

        return matches
    }

    static func stripAnsi(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{1b}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}
