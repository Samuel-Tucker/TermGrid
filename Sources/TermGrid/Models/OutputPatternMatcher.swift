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

/// Scans the first ~20 lines of terminal output for agent startup banners.
/// Once an agent is detected (or 20 lines pass), scanning stops.
struct AgentDetector {
    private var lineBuffer: [UInt8] = []
    private var lineCount = 0
    private(set) var detected: AgentType? = nil

    private static let patterns: [(pattern: String, agent: AgentType)] = [
        ("╭.* Claude",    .claudeCode),
        ("Claude Code",   .claudeCode),
        ("claude>",       .claudeCode),
        ("Welcome back",  .claudeCode),   // Claude's "Welcome back <name>!" greeting
        ("Opus",          .claudeCode),   // Model name in Claude startup
        ("Sonnet",        .claudeCode),   // Model name in Claude startup
        ("Haiku",         .claudeCode),   // Model name in Claude startup
        ("OpenAI Codex",  .codex),
        ("^codex>",       .codex),
        ("Gemini Code",   .gemini),
        ("✦ Gemini",      .gemini),
        ("aider v\\d",    .aider),
        ("Aider v\\d",    .aider),
    ]

    /// Stop scanning after detection or 80 lines or 64KB of buffered data.
    /// Claude Code uses TUI rendering which can take many lines of escape sequences.
    private static let maxBufferSize = 65_536

    var isFinished: Bool { detected != nil || lineCount >= 80 }

    mutating func processChunk(_ bytes: ArraySlice<UInt8>) -> AgentType? {
        guard !isFinished else { return nil }

        for byte in bytes {
            if byte == 0x0A {
                lineCount += 1
                if let line = String(bytes: lineBuffer, encoding: .utf8) {
                    let clean = OutputPatternMatcher.stripAnsi(line)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    for (pattern, agent) in Self.patterns {
                        if clean.range(of: pattern, options: .regularExpression) != nil {
                            detected = agent
                            return agent
                        }
                    }
                }
                lineBuffer.removeAll()
                if lineCount >= 80 { return nil }
            } else {
                lineBuffer.append(byte)
                // Cap buffer to prevent unbounded growth on binary data
                if lineBuffer.count > Self.maxBufferSize {
                    lineCount = 80 // force finish
                    return nil
                }
            }
        }
        return nil
    }
}
