import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Async LLM completion provider using MLX. Runs as an enhancer alongside n-gram predictions.
///
/// Usage:
/// 1. Check `modelManager.isReady` before calling
/// 2. Call `requestCompletion(input:terminalContext:workingDirectory:)` — observes `lastCompletion`
/// 3. Result replaces ghost text if better than n-gram prediction
@MainActor
@Observable
public final class MLXCompletionProvider {
    public let modelManager: ModelManager

    /// Whether the MLX enhancer is enabled by the user.
    public var isEnabled: Bool = false

    /// The most recent MLX completion result (nil if none pending).
    public private(set) var lastCompletion: String?

    /// The input that was used to generate `lastCompletion`.
    /// Used to guard against stale results (C3 fix).
    public private(set) var lastCompletionInput: String?

    /// Monotonic generation ID — incremented on each request (C3 fix).
    public private(set) var generationID: UInt64 = 0

    /// Whether an MLX query is currently in flight.
    public private(set) var isGenerating: Bool = false

    private var debounceTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?

    private static let debounceMs: UInt64 = 150
    private static let maxTokens: Int = 30

    public init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Request an MLX-enhanced completion. Debounced at 150ms.
    public func requestCompletion(
        input: String,
        terminalContext: String = "",
        workingDirectory: String = ""
    ) {
        debounceTask?.cancel()
        generationTask?.cancel()
        lastCompletion = nil
        lastCompletionInput = nil
        generationID &+= 1 // C3 fix: increment generation ID

        guard isEnabled, modelManager.isReady else { return }
        guard input.count >= 2 else { return }

        let currentGenID = generationID
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.debounceMs))
            guard !Task.isCancelled, currentGenID == self.generationID else { return }
            await runGeneration(input: input, terminalContext: terminalContext,
                              workingDirectory: workingDirectory, genID: currentGenID)
        }
    }

    /// Cancel any in-flight MLX query.
    public func cancel() {
        debounceTask?.cancel()
        generationTask?.cancel()
        lastCompletion = nil
        lastCompletionInput = nil
        isGenerating = false
    }

    // MARK: - Private

    private func runGeneration(input: String, terminalContext: String,
                               workingDirectory: String, genID: UInt64) async {
        // Ensure model is loaded into memory
        if !modelManager.isModelLoaded {
            do {
                try await modelManager.loadModel()
            } catch {
                return
            }
        }

        guard let container = modelManager.modelContainer else { return }
        // C3 fix: check generation ID hasn't moved on during load
        guard genID == self.generationID else { return }

        isGenerating = true
        let messages = buildMessages(input: input, terminalContext: terminalContext,
                                     workingDirectory: workingDirectory)

        generationTask = Task { @MainActor in
            do {
                let result = try await generate(container: container, messages: messages)
                // C3 fix: verify this result is still for the current request
                guard !Task.isCancelled, genID == self.generationID else { return }
                let cleaned = cleanCompletion(result, input: input)
                if !cleaned.isEmpty {
                    self.lastCompletion = cleaned
                    self.lastCompletionInput = input
                }
            } catch {
                // Generation failed — silently fall back to n-gram
            }
            self.isGenerating = false
        }
    }

    /// Run generation against the loaded model using the chat template.
    private func generate(container: ModelContainer, messages: [[String: String]]) async throws -> String {
        // Build LMInput from chat messages using the model's tokenizer
        let tokenIds = try await container.applyChatTemplate(messages: messages)
        let input = LMInput(tokens: MLXArray(tokenIds))

        let params = GenerateParameters(
            maxTokens: Self.maxTokens,
            temperature: 0.0 // deterministic completions
        )

        var outputText = ""
        let stream = try await container.generate(input: input, parameters: params)
        // C7 fix: labeled loop so `break` exits the for-await, not just the switch
        generation: for await generation in stream {
            if Task.isCancelled { break generation }
            switch generation {
            case .chunk(let text):
                outputText += text
                if outputText.contains("\n") { break generation }
            case .info:
                break
            case .toolCall:
                break
            }
        }

        return outputText
    }

    /// Build ChatML messages for the model.
    private func buildMessages(input: String, terminalContext: String, workingDirectory: String) -> [[String: String]] {
        var contextSection = ""
        if !terminalContext.isEmpty {
            let lines = terminalContext.components(separatedBy: "\n")
            let last50 = lines.suffix(50).joined(separator: "\n")
            contextSection = "\nRecent terminal output:\n\(last50)\n"
        }

        let cwd = workingDirectory.isEmpty ? "unknown" : workingDirectory

        return [
            [
                "role": "system",
                "content": """
                Complete the user's partial terminal command or prompt. \
                Respond with ONLY the completion text after the cursor position. \
                Do not repeat what the user has already typed. \
                Keep completions short and practical (flags, arguments, paths).
                """
            ],
            [
                "role": "user",
                "content": "Context: macOS terminal, working directory \(cwd)\(contextSection)\nPartial input: \(input)"
            ]
        ]
    }

    /// Clean up the model output — remove repeated input, trim whitespace, cap length.
    private func cleanCompletion(_ raw: String, input: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any ChatML markers that leaked through
        if let range = result.range(of: "<|") {
            result = String(result[result.startIndex..<range.lowerBound])
        }

        // If model repeated the input, strip it (case-sensitive to avoid W5 corruption)
        let trimmedInput = input.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix(trimmedInput) {
            result = String(result.dropFirst(trimmedInput.count))
                .trimmingCharacters(in: .init(charactersIn: " "))
        }

        // Cap at first newline
        if let nlIdx = result.firstIndex(of: "\n") {
            result = String(result[result.startIndex..<nlIdx])
        }

        // Cap at 80 characters
        if result.count > 80 {
            result = String(result.prefix(80))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
