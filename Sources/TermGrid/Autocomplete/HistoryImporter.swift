import Foundation

struct HistoryEntry {
    let command: String
    let timestamp: Date
}

enum HistoryImporter {
    /// Parse zsh history file format: `: timestamp:duration;command`
    static func parseZshHistory(at path: String) -> [HistoryEntry] {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return [] }

        var entries: [HistoryEntry] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(": ") else {
                // Plain history line (no timestamp)
                if !trimmed.isEmpty {
                    entries.append(HistoryEntry(command: sanitize(trimmed), timestamp: Date()))
                }
                continue
            }

            // Format: `: 1710000000:0;git status`
            let afterColon = trimmed.dropFirst(2) // drop ": "
            guard let semicolonIdx = afterColon.firstIndex(of: ";") else { continue }

            let metaPart = afterColon[afterColon.startIndex..<semicolonIdx]
            let command = String(afterColon[afterColon.index(after: semicolonIdx)...])
            guard !command.isEmpty else { continue }

            // Parse timestamp from "1710000000:0"
            let metaStr = String(metaPart)
            let timestamp: Date
            if let colonIdx = metaStr.firstIndex(of: ":"),
               let ts = Double(metaStr[metaStr.startIndex..<colonIdx]) {
                timestamp = Date(timeIntervalSince1970: ts)
            } else if let ts = Double(metaStr) {
                timestamp = Date(timeIntervalSince1970: ts)
            } else {
                timestamp = Date()
            }

            entries.append(HistoryEntry(command: sanitize(command), timestamp: timestamp))
        }

        return entries
    }

    /// Sanitize secrets from command strings.
    static func sanitize(_ command: String) -> String {
        var result = command

        // Pattern: KEY=value or export KEY=value (case-insensitive for var names) (W2 fix)
        let envPattern = #"(?:export\s+)?[A-Za-z_][A-Za-z0-9_]*=\S+"#
        if let regex = try? NSRegularExpression(pattern: envPattern) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)
        }

        // Common secret prefixes — replace ALL occurrences (C3 fix)
        let secretPrefixes = ["sk-", "ghp_", "glpat-", "Bearer ", "token "]
        for prefix in secretPrefixes {
            while let range = result.range(of: prefix) {
                let afterPrefix = result[range.upperBound...]
                let tokenEnd = afterPrefix.firstIndex(where: { $0.isWhitespace }) ?? afterPrefix.endIndex
                result.replaceSubrange(range.lowerBound..<tokenEnd, with: "<REDACTED>")
            }
        }

        return result
    }

    /// Import entries into the autocomplete system.
    static func importInto(
        db: AutocompleteDB,
        trigramEngine: TrigramEngine,
        trie: InMemoryTrie,
        entries: [HistoryEntry]
    ) throws -> Int {
        var imported = 0
        for entry in entries {
            let command = entry.command
            guard !command.isEmpty else { continue }

            let ts = entry.timestamp.timeIntervalSince1970

            // Insert into corpus
            try db.insertCorpus(CorpusRecord(
                id: nil, content: command, domain: "shell",
                timestamp: ts, acceptedFromSuggestion: 0, workingDirectory: ""
            ))

            // Tokenize and record trigrams
            let tokens = Tokenizer.tokenize(command)
            try trigramEngine.record(tokens: tokens)

            // Build prefix entries
            for token in tokens {
                for len in 1...token.count {
                    let prefix = String(token.prefix(len))
                    try db.upsertPrefix(PrefixRecord(
                        prefix: prefix, completion: token,
                        frequency: 1, lastUsed: ts, domain: "shell"
                    ))
                    trie.insert(prefix: prefix, completion: token,
                               frequency: 1, lastUsed: ts, domain: "shell")
                }
            }

            imported += 1
        }
        return imported
    }
}
