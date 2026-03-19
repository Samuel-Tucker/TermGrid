import Foundation

struct TrigramKey: Hashable {
    let w1: String
    let w2: String
}

struct TrigramPrediction {
    let token: String
    let score: Double
    let confidence: Double
}

final class TrigramEngine {
    private let db: AutocompleteDB
    private var cache: [TrigramKey: [String: (count: Int, lastUsed: Double, confidence: Double)]] = [:]

    init(db: AutocompleteDB) {
        self.db = db
    }

    /// Load all trigrams from DB into memory cache.
    func loadCache() throws {
        let records = try db.allTrigrams()
        cache.removeAll()
        for r in records {
            let key = TrigramKey(w1: r.w1, w2: r.w2)
            if cache[key] == nil { cache[key] = [:] }
            cache[key]![r.w3] = (count: r.count, lastUsed: r.lastUsed, confidence: r.confidence)
        }
    }

    /// Record tokens: updates both in-memory cache and DB.
    func record(tokens: [String]) throws {
        recordInMemory(tokens: tokens, timestamp: Date().timeIntervalSince1970)
        try persistTokens(tokens, timestamp: Date().timeIntervalSince1970)
    }

    /// Update in-memory cache only (safe to call from @MainActor).
    func recordInMemory(tokens: [String], timestamp: Double) {
        guard !tokens.isEmpty else { return }
        let padded = ["<START>", "<START>"] + tokens

        for i in 0..<(padded.count - 2) {
            let key = TrigramKey(w1: padded[i], w2: padded[i + 1])
            let w3 = padded[i + 2]
            if cache[key] == nil { cache[key] = [:] }
            if var entry = cache[key]![w3] {
                entry.count += 1
                entry.lastUsed = timestamp
                cache[key]![w3] = entry
            } else {
                cache[key]![w3] = (count: 1, lastUsed: timestamp, confidence: Scorer.baseCorpusConfidence)
            }
        }
    }

    /// Persist tokens to DB only (safe to call from detached task).
    func persistTokens(_ tokens: [String], timestamp: Double) throws {
        guard !tokens.isEmpty else { return }
        let padded = ["<START>", "<START>"] + tokens

        for i in 0..<(padded.count - 2) {
            try db.upsertTrigram(TrigramRecord(
                w1: padded[i], w2: padded[i + 1], w3: padded[i + 2],
                count: 1, lastUsed: timestamp, confidence: Scorer.baseCorpusConfidence
            ))
        }
    }

    /// Predict the next token given previous two tokens.
    func predict(w1: String, w2: String, limit: Int = 5, now: Date = Date()) -> [TrigramPrediction] {
        let key = TrigramKey(w1: w1, w2: w2)
        guard let entries = cache[key] else { return [] }

        return entries.compactMap { (w3, entry) -> TrigramPrediction? in
            guard entry.confidence >= Scorer.confidenceThreshold else { return nil }
            let score = Scorer.score(
                count: entry.count,
                lastUsed: Date(timeIntervalSince1970: entry.lastUsed),
                confidence: entry.confidence,
                now: now
            )
            return TrigramPrediction(token: w3, score: score, confidence: entry.confidence)
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    /// Update confidence for a specific trigram (accept/reject feedback).
    func updateConfidence(w1: String, w2: String, w3: String, confidence: Double) throws {
        let key = TrigramKey(w1: w1, w2: w2)
        if cache[key] != nil, cache[key]![w3] != nil {
            cache[key]![w3]!.confidence = confidence
        }
        try db.updateTrigramConfidence(w1: w1, w2: w2, w3: w3, confidence: confidence)
    }
}
