import Foundation

struct ComposeHistoryEntry: Codable, Identifiable {
    let id: UUID
    let content: String
    let timestamp: Date

    /// First line, truncated to 40 chars
    var displayTitle: String {
        let firstLine = content.components(separatedBy: .newlines).first ?? content
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(40)) + (trimmed.count > 40 ? "..." : "")
    }

    var lineCount: Int {
        content.components(separatedBy: .newlines).count
    }

    var relativeTimestamp: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        switch seconds {
        case ..<60:       return "now"
        case ..<3600:     return "\(seconds / 60)m ago"
        case ..<86400:    return "\(seconds / 3600)h ago"
        case ..<604800:   return "\(seconds / 86400)d ago"
        default:          return "\(seconds / 604800)w ago"
        }
    }
}

// MARK: - Fuzzy Match

/// Returns matched character indices if `query` fuzzy-matches `text`, nil otherwise.
func fuzzyMatch(query: String, in text: String) -> [String.Index]? {
    guard !query.isEmpty else { return [] }
    let queryLower = query.lowercased()
    let textLower = text.lowercased()
    var matchedIndices: [String.Index] = []
    var queryIndex = queryLower.startIndex

    for textIndex in textLower.indices {
        if textLower[textIndex] == queryLower[queryIndex] {
            matchedIndices.append(textIndex)
            queryIndex = queryLower.index(after: queryIndex)
            if queryIndex == queryLower.endIndex { return matchedIndices }
        }
    }
    return nil // not all query chars were matched
}
