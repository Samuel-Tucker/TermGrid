@testable import TermGrid
import Testing
import Foundation

@Suite("AutocompleteDB Tests")
struct AutocompleteDBTests {

    private func makeDB() throws -> AutocompleteDB {
        try AutocompleteDB(path: ":memory:")
    }

    @Test func schemaCreation() throws {
        let db = try makeDB()
        // Should not throw — tables exist
        let corpus = try db.recentCorpus(limit: 1)
        #expect(corpus.isEmpty)
    }

    @Test func corpusInsertAndQuery() throws {
        let db = try makeDB()
        try db.insertCorpus(CorpusRecord(
            id: nil, content: "git status", domain: "shell",
            timestamp: Date().timeIntervalSince1970,
            acceptedFromSuggestion: 0, workingDirectory: ""
        ))
        let results = try db.recentCorpus(limit: 10)
        #expect(results.count == 1)
        #expect(results[0].content == "git status")
    }

    @Test func trigramUpsertAndQuery() throws {
        let db = try makeDB()
        let ts = Date().timeIntervalSince1970
        try db.upsertTrigram(TrigramRecord(
            w1: "<START>", w2: "git", w3: "status",
            count: 1, lastUsed: ts, confidence: 0.7
        ))
        try db.upsertTrigram(TrigramRecord(
            w1: "<START>", w2: "git", w3: "status",
            count: 1, lastUsed: ts, confidence: 0.7
        ))
        let results = try db.queryTrigrams(w1: "<START>", w2: "git")
        #expect(results.count == 1)
        #expect(results[0].count == 2) // upserted
    }

    @Test func prefixUpsertAndQuery() throws {
        let db = try makeDB()
        let ts = Date().timeIntervalSince1970
        try db.upsertPrefix(PrefixRecord(
            prefix: "gi", completion: "git", frequency: 1, lastUsed: ts, domain: "shell"
        ))
        try db.upsertPrefix(PrefixRecord(
            prefix: "gi", completion: "git", frequency: 1, lastUsed: ts, domain: "shell"
        ))
        let results = try db.queryPrefixes(prefix: "gi", domain: "shell")
        #expect(results.count == 1)
        #expect(results[0].frequency == 2) // upserted
    }

    @Test func pruneRemovesOldEntries() throws {
        let db = try makeDB()
        let oldTs = Date().timeIntervalSince1970 - (100 * 86400) // 100 days ago
        try db.upsertTrigram(TrigramRecord(
            w1: "a", w2: "b", w3: "c",
            count: 1, lastUsed: oldTs, confidence: 0.05
        ))
        try db.pruneOldEntries(olderThan: 90, minConfidence: 0.1)
        let results = try db.allTrigrams()
        #expect(results.isEmpty)
    }

    @Test func pruneKeepsRecentEntries() throws {
        let db = try makeDB()
        let ts = Date().timeIntervalSince1970
        try db.upsertTrigram(TrigramRecord(
            w1: "a", w2: "b", w3: "c",
            count: 1, lastUsed: ts, confidence: 0.05
        ))
        try db.pruneOldEntries(olderThan: 90, minConfidence: 0.1)
        let results = try db.allTrigrams()
        #expect(results.count == 1)
    }
}
