@testable import TermGrid
import Testing
import Foundation

@Suite("Scorer Tests")
struct ScorerTests {

    @Test func recentCommandScoresHigh() {
        let score = Scorer.score(
            count: 5,
            lastUsed: Date(),
            confidence: 1.0
        )
        // 5 * 1.0 * 1.0 = 5.0
        #expect(score > 4.9 && score <= 5.0)
    }

    @Test func oldCommandDecays() {
        let thirtyDaysAgo = Date(timeIntervalSinceNow: -30 * 86400)
        let score = Scorer.score(
            count: 10,
            lastUsed: thirtyDaysAgo,
            confidence: 1.0
        )
        // 10 * ~0.15 * 1.0 ≈ 1.5
        #expect(score < 3.0)
        #expect(score > 0.5)
    }

    @Test func confidenceGating() {
        #expect(Scorer.confidenceThreshold == 0.6)
        #expect(Scorer.baseCorpusConfidence == 0.7)
        #expect(Scorer.baseCorpusConfidence >= Scorer.confidenceThreshold)
    }

    @Test func boostConfidence() {
        let initial = 0.5
        let boosted = Scorer.boostConfidence(initial)
        // 0.15 * 1.0 + 0.85 * 0.5 = 0.575
        #expect(boosted > initial)
        #expect(abs(boosted - 0.575) < 0.001)
    }

    @Test func doubleBoostCrossesThreshold() {
        let once = Scorer.boostConfidence(0.5)
        let twice = Scorer.boostConfidence(once)
        // 0.575 → 0.15 + 0.85 * 0.575 = 0.63875
        #expect(twice >= Scorer.confidenceThreshold)
    }

    @Test func penalizeConfidence() {
        let initial = 0.7
        let penalized = Scorer.penalizeConfidence(initial)
        // 0.85 * 0.7 = 0.595
        #expect(penalized < initial)
        #expect(abs(penalized - 0.595) < 0.001)
    }

    @Test func baseCorpusAboveThreshold() {
        #expect(Scorer.baseCorpusConfidence > Scorer.confidenceThreshold)
    }

    @Test func zeroCountScoresZero() {
        let score = Scorer.score(count: 0, lastUsed: Date(), confidence: 1.0)
        #expect(score == 0.0)
    }
}
