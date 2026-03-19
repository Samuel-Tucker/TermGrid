import Foundation

struct PrefixMatch {
    let completion: String
    let score: Double
}

final class InMemoryTrie {
    private final class Node {
        var children: [Character: Node] = [:]
        var completions: [(text: String, frequency: Int, lastUsed: Double, domain: String)] = []
    }

    private let root = Node()
    private(set) var entryCount = 0

    /// Bulk load from DB prefix records.
    func load(from records: [PrefixRecord]) {
        for record in records {
            insert(prefix: record.prefix, completion: record.completion,
                   frequency: record.frequency, lastUsed: record.lastUsed,
                   domain: record.domain)
        }
    }

    func insert(prefix: String, completion: String, frequency: Int,
                lastUsed: Double, domain: String) {
        let key = prefix.lowercased()
        var node = root
        for char in key {
            if node.children[char] == nil {
                node.children[char] = Node()
            }
            node = node.children[char]!
        }

        if let idx = node.completions.firstIndex(where: { $0.text == completion && $0.domain == domain }) {
            node.completions[idx].frequency += frequency
            node.completions[idx].lastUsed = max(node.completions[idx].lastUsed, lastUsed)
        } else {
            node.completions.append((text: completion, frequency: frequency, lastUsed: lastUsed, domain: domain))
            entryCount += 1
        }
    }

    func search(prefix: String, domain: String, limit: Int = 10, now: Date = Date()) -> [PrefixMatch] {
        let key = prefix.lowercased()
        var node = root
        for char in key {
            guard let next = node.children[char] else { return [] }
            node = next
        }

        let candidates = node.completions.filter { $0.domain == domain }
        let scored = candidates.map { entry -> PrefixMatch in
            let score = Scorer.score(
                count: entry.frequency,
                lastUsed: Date(timeIntervalSince1970: entry.lastUsed),
                confidence: Scorer.baseCorpusConfidence,
                now: now
            )
            return PrefixMatch(completion: entry.text, score: score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
