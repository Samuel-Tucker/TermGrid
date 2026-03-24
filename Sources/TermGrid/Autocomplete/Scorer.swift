import Foundation

enum Scorer {
    static let defaultHalfLife: Double = 11.0
    static let confidenceThreshold: Double = 0.6
    static let baseCorpusConfidence: Double = 0.7
    private static let emaAlpha: Double = 0.15

    /// Exponential decay score.
    /// `count` * 0.5^(days / halfLife) * confidence
    static func score(count: Int, lastUsed: Date, confidence: Double,
                      now: Date = Date(), halfLife: Double = defaultHalfLife) -> Double {
        let days = max(now.timeIntervalSince(lastUsed) / 86400, 0)
        let decay = pow(0.5, days / halfLife)
        return Double(count) * decay * confidence
    }

    /// EMA boost toward 1.0 on accept.
    static func boostConfidence(_ current: Double) -> Double {
        min(1.0, emaAlpha * 1.0 + (1.0 - emaAlpha) * current)
    }

    /// EMA decay on reject — floor at 0.3 to allow recovery (W1 fix).
    static func penalizeConfidence(_ current: Double) -> Double {
        max(0.3, (1.0 - emaAlpha) * current)
    }
}
