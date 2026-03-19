@testable import TermGrid
import Testing
import Foundation

@Suite("TrigramEngine Tests")
struct TrigramEngineTests {

    private func makeEngine() throws -> (TrigramEngine, AutocompleteDB) {
        let db = try AutocompleteDB(path: ":memory:")
        let engine = TrigramEngine(db: db)
        return (engine, db)
    }

    @Test func recordAndPredict() throws {
        let (engine, _) = try makeEngine()
        try engine.record(tokens: ["git", "commit", "-m"])

        // Load cache for predictions
        try engine.loadCache()

        let predictions = engine.predict(w1: "<START>", w2: "git")
        #expect(!predictions.isEmpty)
        #expect(predictions[0].token == "commit")
    }

    @Test func unknownContextReturnsEmpty() throws {
        let (engine, _) = try makeEngine()
        try engine.record(tokens: ["git", "status"])
        try engine.loadCache()

        let predictions = engine.predict(w1: "unknown", w2: "context")
        #expect(predictions.isEmpty)
    }

    @Test func confidenceFilter() throws {
        let (engine, db) = try makeEngine()

        // Insert with low confidence directly
        try db.upsertTrigram(TrigramRecord(
            w1: "a", w2: "b", w3: "c",
            count: 10, lastUsed: Date().timeIntervalSince1970,
            confidence: 0.3 // below 0.6 threshold
        ))
        try engine.loadCache()

        let predictions = engine.predict(w1: "a", w2: "b")
        #expect(predictions.isEmpty) // filtered out by confidence
    }

    @Test func repeatedRecordIncrementsCount() throws {
        let (engine, _) = try makeEngine()
        try engine.record(tokens: ["docker", "run"])
        try engine.record(tokens: ["docker", "run"])
        try engine.loadCache()

        let predictions = engine.predict(w1: "<START>", w2: "docker")
        #expect(!predictions.isEmpty)
        // Score should be higher due to count=2
    }

    @Test func updateConfidence() throws {
        let (engine, db) = try makeEngine()
        let ts = Date().timeIntervalSince1970
        try db.upsertTrigram(TrigramRecord(
            w1: "git", w2: "commit", w3: "-m",
            count: 5, lastUsed: ts, confidence: 0.7
        ))
        try engine.loadCache()

        let boosted = Scorer.boostConfidence(0.7)
        try engine.updateConfidence(w1: "git", w2: "commit", w3: "-m", confidence: boosted)

        try engine.loadCache()
        let predictions = engine.predict(w1: "git", w2: "commit")
        #expect(!predictions.isEmpty)
        #expect(predictions[0].confidence > 0.7)
    }
}
