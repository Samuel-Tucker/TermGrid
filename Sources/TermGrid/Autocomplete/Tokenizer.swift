import Foundation

enum Tokenizer {
    /// Whitespace-split with quote awareness.
    /// `"git commit -m \"hello world\""` → `["git", "commit", "-m", "\"hello world\""]`
    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote: Character? = nil

        for char in input {
            if let q = inQuote {
                current.append(char)
                if char == q { inQuote = nil }
            } else if char == "\"" || char == "'" {
                inQuote = char
                current.append(char)
            } else if char.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Split input into (context before last token, partial last token).
    /// `"git comm"` → `(context: "git", partial: "comm")`
    static func extractPartial(_ input: String) -> (context: String, partial: String) {
        let trimmed = input
        guard !trimmed.isEmpty else { return ("", "") }

        // If ends with space, the partial is empty
        if trimmed.last?.isWhitespace == true {
            return (trimmed.trimmingCharacters(in: .whitespaces), "")
        }

        let tokens = tokenize(trimmed)
        guard !tokens.isEmpty else { return ("", "") }

        let partial = tokens.last!
        let context = tokens.dropLast().joined(separator: " ")
        return (context, partial)
    }

    /// Return the last N tokens from the input.
    static func lastNTokens(_ input: String, n: Int) -> [String] {
        let tokens = tokenize(input)
        return Array(tokens.suffix(n))
    }
}
