import Foundation
import Observation
import TermGridMLX

struct Prediction: Equatable {
    let text: String
    let score: Double
    let source: PredictionSource
}

enum PredictionSource {
    case trigram, prefix, corpus, mlx
}

@MainActor
@Observable
final class CompletionEngine {
    private(set) var predictions: [Prediction] = []

    /// MLX completion provider — set externally, used as async enhancer.
    var mlxProvider: MLXCompletionProvider?

    /// Most recent MLX-enhanced prediction (replaces n-gram ghost when available).
    /// C1 fix: directly populated by observing mlxProvider.lastCompletion.
    private(set) var mlxPrediction: String?

    /// The input snapshot that generated the current mlxPrediction (C3 fix).
    private(set) var mlxPredictionInput: String?

    /// Callback to extract terminal context on-demand (C4 fix: avoids extracting on every keystroke).
    var terminalContextProvider: (() -> String)?

    private var db: AutocompleteDB?
    private var trigramEngine: TrigramEngine?
    private var trie: InMemoryTrie?
    private var debounceTask: Task<Void, Never>?
    private var mlxObservationTask: Task<Void, Never>?
    private var bootstrapped = false

    func bootstrap() async throws {
        guard !bootstrapped else { return }
        bootstrapped = true // set early to prevent double-bootstrap (W1 fix)

        let database = try AutocompleteDB()
        let trigrams = TrigramEngine(db: database)
        let prefixTrie = InMemoryTrie()

        // Load caches from DB
        try trigrams.loadCache()
        let allPrefixes = try database.allPrefixes()
        prefixTrie.load(from: allPrefixes)

        // Load base corpus on first run (if trie is empty)
        if prefixTrie.entryCount == 0 {
            try loadBaseCorpus(db: database, trigramEngine: trigrams, trie: prefixTrie)
            try trigrams.loadCache() // C4 fix: reload cache after base corpus load
        }

        self.db = database
        self.trigramEngine = trigrams
        self.trie = prefixTrie
    }

    /// Request predictions for the current input. 50ms debounce.
    /// When MLX is enabled and n-gram confidence is low (< 0.6), dispatches async MLX query.
    /// C4 fix: terminal context is extracted lazily only when MLX is actually dispatched.
    func requestPredictions(for input: String, workingDirectory: String = "",
                            domain: String = "shell") {
        debounceTask?.cancel()
        mlxPrediction = nil
        mlxPredictionInput = nil
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            computePredictions(for: input, domain: domain)

            // Hybrid routing: if best n-gram confidence < 0.6, dispatch MLX enhancer
            let bestScore = predictions.first?.score ?? 0
            if bestScore < Scorer.confidenceThreshold,
               let mlx = mlxProvider, mlx.isEnabled {
                // C4 fix: extract terminal context only when MLX is dispatched (not every keystroke)
                let termCtx = terminalContextProvider?() ?? ""
                mlx.requestCompletion(
                    input: input,
                    terminalContext: termCtx,
                    workingDirectory: workingDirectory
                )
                // C1 fix: start observing the provider for results
                startMLXObservation()
            } else {
                mlxProvider?.cancel()
            }
        }
    }

    func clearPredictions() {
        debounceTask?.cancel()
        mlxObservationTask?.cancel()
        mlxProvider?.cancel()
        mlxPrediction = nil
        mlxPredictionInput = nil
        predictions = []
    }

    // MARK: - MLX Observation (C1 fix)

    /// Poll for MLX provider result. Lightweight — checks every 50ms while generating.
    private func startMLXObservation() {
        mlxObservationTask?.cancel()
        mlxObservationTask = Task { @MainActor in
            guard let mlx = mlxProvider else { return }
            // Wait for generation to complete
            while mlx.isGenerating || mlx.lastCompletion == nil {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                if !mlx.isGenerating { break }
            }
            guard !Task.isCancelled else { return }
            if let result = mlx.lastCompletion, let inputSnapshot = mlx.lastCompletionInput {
                self.mlxPrediction = result
                self.mlxPredictionInput = inputSnapshot
            }
        }
    }

    /// Record a sent command for learning.
    /// All mutations happen on @MainActor to avoid data races (C1 fix).
    /// DB writes are dispatched to a detached task separately.
    func recordCommand(_ command: String, workingDirectory: String = "",
                       acceptedSuggestion: Bool = false) {
        guard let db, let trigramEngine, let trie else { return }

        let ts = Date().timeIntervalSince1970
        let tokens = Tokenizer.tokenize(command)

        // Update in-memory structures on main actor (C1 fix: no data race)
        trigramEngine.recordInMemory(tokens: tokens, timestamp: ts)

        for token in tokens {
            for len in 1...token.count { // C2 fix: inclusive range for single-char tokens
                let prefix = String(token.prefix(len))
                trie.insert(prefix: prefix, completion: token,
                           frequency: 1, lastUsed: ts, domain: "shell")
            }
        }

        // Persist to DB off main actor
        Task.detached {
            try db.insertCorpus(CorpusRecord(
                id: nil, content: command, domain: "shell",
                timestamp: ts,
                acceptedFromSuggestion: acceptedSuggestion ? 1 : 0,
                workingDirectory: workingDirectory
            ))

            try trigramEngine.persistTokens(tokens, timestamp: ts)

            for token in tokens {
                for len in 1...token.count {
                    let prefix = String(token.prefix(len))
                    try db.upsertPrefix(PrefixRecord(
                        prefix: prefix, completion: token,
                        frequency: 1, lastUsed: ts, domain: "shell"
                    ))
                }
            }
        }
    }

    /// Record a rejection — user typed over the ghost suggestion.
    func recordRejection(input: String, rejectedSuggestion: String) {
        guard let trigramEngine else { return }

        let tokens = Tokenizer.tokenize(input)
        guard tokens.count >= 2 else { return }

        let w1 = tokens.count >= 3 ? tokens[tokens.count - 3] : "<START>"
        let w2 = tokens[tokens.count - 2]
        let w3 = rejectedSuggestion.split(separator: " ").first.map(String.init) ?? rejectedSuggestion

        // Find current confidence and penalize
        let preds = trigramEngine.predict(w1: w1, w2: w2, limit: 20)
        if let match = preds.first(where: { $0.token == w3 }) {
            let newConf = Scorer.penalizeConfidence(match.confidence)
            try? trigramEngine.updateConfidence(w1: w1, w2: w2, w3: w3, confidence: newConf)
        }
    }

    /// Boost confidence for an accepted ghost suggestion.
    func recordAcceptance(input: String, acceptedSuggestion: String) {
        guard let trigramEngine else { return }

        let tokens = Tokenizer.tokenize(input)
        let w1: String
        let w2: String
        if tokens.count >= 2 {
            w1 = tokens[tokens.count - 2]
            w2 = tokens[tokens.count - 1]
        } else if tokens.count == 1 {
            w1 = "<START>"
            w2 = tokens[0]
        } else {
            return
        }

        let w3 = acceptedSuggestion.split(separator: " ").first.map(String.init) ?? acceptedSuggestion

        let preds = trigramEngine.predict(w1: w1, w2: w2, limit: 20)
        if let match = preds.first(where: { $0.token == w3 }) {
            let newConf = Scorer.boostConfidence(match.confidence)
            try? trigramEngine.updateConfidence(w1: w1, w2: w2, w3: w3, confidence: newConf)
        }
    }

    // MARK: - Private

    private func computePredictions(for input: String, domain: String) {
        guard let trigramEngine, let trie else { return }
        guard input.count >= 2 else {
            predictions = []
            return
        }

        var results: [Prediction] = []
        let (context, partial) = Tokenizer.extractPartial(input)

        // Trigram predictions — use correct context window (W3 fix)
        let contextTokens = Tokenizer.tokenize(context)
        if partial.isEmpty {
            // Trailing space: user wants next token. Use last two context tokens.
            let tokens = contextTokens
            if tokens.count >= 2 {
                let w1 = tokens[tokens.count - 2]
                let w2 = tokens[tokens.count - 1]
                let trigramResults = trigramEngine.predict(w1: w1, w2: w2)
                for t in trigramResults {
                    results.append(Prediction(text: t.token, score: t.score, source: .trigram))
                }
            } else if tokens.count == 1 {
                let trigramResults = trigramEngine.predict(w1: "<START>", w2: tokens[0])
                for t in trigramResults {
                    results.append(Prediction(text: t.token, score: t.score, source: .trigram))
                }
            }
        } else {
            // Mid-word: use context tokens before the partial
            let tokens = contextTokens
            if tokens.count >= 2 {
                let w1 = tokens[tokens.count - 2]
                let w2 = tokens[tokens.count - 1]
                let trigramResults = trigramEngine.predict(w1: w1, w2: w2)
                for t in trigramResults {
                    results.append(Prediction(text: t.token, score: t.score, source: .trigram))
                }
            } else if tokens.count == 1 {
                let trigramResults = trigramEngine.predict(w1: "<START>", w2: tokens[0])
                for t in trigramResults {
                    results.append(Prediction(text: t.token, score: t.score, source: .trigram))
                }
            }
        }

        // Prefix predictions
        if !partial.isEmpty {
            let prefixResults = trie.search(prefix: partial, domain: domain)
            for p in prefixResults {
                if !results.contains(where: { $0.text == p.completion }) {
                    results.append(Prediction(text: p.completion, score: p.score, source: .prefix))
                }
            }
        }

        predictions = results.sorted { $0.score > $1.score }.prefix(5).map { $0 }
    }

    private func loadBaseCorpus(db: AutocompleteDB, trigramEngine: TrigramEngine, trie: InMemoryTrie) throws {
        guard let url = Bundle.main.url(forResource: "base-corpus", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }

        struct BaseCorpus: Codable {
            let version: Int
            let entries: [Entry]
            struct Entry: Codable {
                let command: String
                let domain: String
            }
        }

        guard let corpus = try? JSONDecoder().decode(BaseCorpus.self, from: data) else { return }

        let ts = Date().timeIntervalSince1970
        for entry in corpus.entries {
            try db.insertCorpus(CorpusRecord(
                id: nil, content: entry.command, domain: entry.domain,
                timestamp: ts, acceptedFromSuggestion: 0, workingDirectory: ""
            ))

            let tokens = Tokenizer.tokenize(entry.command)

            let padded = ["<START>", "<START>"] + tokens
            for i in 0..<(padded.count - 2) {
                try db.upsertTrigram(TrigramRecord(
                    w1: padded[i], w2: padded[i + 1], w3: padded[i + 2],
                    count: 1, lastUsed: ts,
                    confidence: Scorer.baseCorpusConfidence
                ))
            }

            for token in tokens {
                for len in 1...token.count { // C2 fix: inclusive range
                    let prefix = String(token.prefix(len))
                    try db.upsertPrefix(PrefixRecord(
                        prefix: prefix, completion: token,
                        frequency: 1, lastUsed: ts, domain: entry.domain
                    ))
                    trie.insert(prefix: prefix, completion: token,
                               frequency: 1, lastUsed: ts, domain: entry.domain)
                }
            }
        }
    }
}
