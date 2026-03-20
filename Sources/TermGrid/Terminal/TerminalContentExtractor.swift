import Foundation

struct ExtractedContent {
    let text: String
    let lineCount: Int
    let wasTruncated: Bool
}

struct TerminalContentExtractor {

    /// Extract the most recent terminal output after the last prompt line.
    static func extractLastOutput(from rawText: String, maxLines: Int = 1000) -> ExtractedContent {
        guard !rawText.isEmpty else {
            return ExtractedContent(text: "", lineCount: 0, wasTruncated: false)
        }

        let lines = rawText.components(separatedBy: "\n").map { stripAnsi($0) }

        let outputLines: ArraySlice<String>
        if let promptIdx = findLastPromptIndex(in: lines) {
            let start = promptIdx + 1
            if start < lines.count {
                outputLines = lines[start...]
            } else {
                outputLines = []
            }
        } else {
            // No prompt found: use last 200 lines as fallback
            let fallback = min(200, lines.count)
            outputLines = lines[(lines.count - fallback)...]
        }

        let wasTruncated = outputLines.count > maxLines
        let capped = wasTruncated ? outputLines.prefix(maxLines) : outputLines[outputLines.startIndex..<outputLines.endIndex]
        let text = capped.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ExtractedContent(
            text: text,
            lineCount: capped.count,
            wasTruncated: wasTruncated
        )
    }

    /// Remove ANSI escape sequences and non-printable control characters.
    static func stripAnsi(_ text: String) -> String {
        var result = text

        // CSI sequences: ESC [ ... final byte
        let csi = try! NSRegularExpression(pattern: "\\x1b\\[[0-9;?]*[a-zA-Z]")
        result = csi.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")

        // OSC sequences: ESC ] ... (terminated by BEL or ST)
        let osc = try! NSRegularExpression(pattern: "\\x1b\\].*?(\\x07|\\x1b\\\\)", options: .dotMatchesLineSeparators)
        result = osc.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")

        // Single-char ESC sequences: ESC followed by a letter
        let singleEsc = try! NSRegularExpression(pattern: "\\x1b[A-Za-z]")
        result = singleEsc.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")

        // Strip remaining control characters except \n (0x0A) and \t (0x09)
        result = String(result.unicodeScalars.filter { scalar in
            scalar.value == 0x0A || scalar.value == 0x09 || scalar.value >= 0x20
        })

        return result
    }

    /// Walk backward through lines to find the last shell prompt.
    /// Returns the index of the prompt line, or nil if none found.
    static func findLastPromptIndex(in lines: [String]) -> Int? {
        let patterns: [NSRegularExpression] = [
            try! NSRegularExpression(pattern: "^\\s*[$%>]\\s*$"),
            try! NSRegularExpression(pattern: "^\\s*[\u{2570}\u{256F}]"),
            try! NSRegularExpression(pattern: "^\\s*codex>"),
            try! NSRegularExpression(pattern: "^\\s*aider>"),
            try! NSRegularExpression(pattern: "^\\S+@\\S+.*[$%#]\\s*$"),
        ]

        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            let line = lines[i]
            let range = NSRange(line.startIndex..., in: line)
            for pattern in patterns {
                if pattern.firstMatch(in: line, range: range) != nil {
                    return i
                }
            }
        }
        return nil
    }
}
