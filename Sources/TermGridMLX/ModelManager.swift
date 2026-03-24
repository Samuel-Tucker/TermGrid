import Foundation
import MLXLLM
import MLXLMCommon

/// Manages MLX model lifecycle: download, storage, status tracking, removal.
@MainActor
@Observable
public final class ModelManager {
    public enum Status: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case loading
        case error(String)

        public static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded): true
            case (.downloading(let a), .downloading(let b)): a == b
            case (.ready, .ready): true
            case (.loading, .loading): true
            case (.error(let a), .error(let b)): a == b
            default: false
            }
        }
    }

    public private(set) var status: Status = .notDownloaded
    public private(set) var modelSizeBytes: Int64 = 0

    /// The loaded model container, ready for inference.
    private(set) var modelContainer: ModelContainer?

    static let modelConfiguration = ModelConfiguration(
        id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
        defaultPrompt: ""
    )
    static let expectedSizeMB: Int = 300

    private var downloadTask: Task<Void, Error>?
    private var loadTask: Task<ModelContainer, Error>? // C6 fix: shared load task

    public init() {
        // C5 fix: only check existence (fast), defer size to background
        checkLocalModelFast()
    }

    /// Fast check — just file existence, no directory enumeration (C5 fix).
    private func checkLocalModelFast() {
        let hubCache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let modelSlug = Self.modelConfiguration.name.replacingOccurrences(of: "/", with: "--")
        let cachedDir = hubCache.appendingPathComponent("models--\(modelSlug)")
        if FileManager.default.fileExists(atPath: cachedDir.path) {
            status = .ready
            // Defer size calculation to background (C5 fix)
            let url = cachedDir
            Task.detached {
                let size = Self.calculateDirectorySize(url)
                await MainActor.run { self.modelSizeBytes = size }
            }
        } else {
            status = .notDownloaded
        }
    }

    /// Download and prepare the model from HuggingFace Hub.
    public func downloadModel() {
        // C2 fix: allow retry from error state
        switch status {
        case .notDownloaded, .error:
            break
        default:
            return
        }
        status = .downloading(progress: 0)

        downloadTask = Task {
            do {
                let container = try await LLMModelFactory.shared.loadContainer(
                    configuration: Self.modelConfiguration
                ) { progress in
                    Task { @MainActor in
                        self.status = .downloading(progress: progress.fractionCompleted)
                    }
                }

                await MainActor.run {
                    self.modelContainer = container
                    self.status = .ready
                    self.checkLocalModelFast()
                }
            } catch {
                await MainActor.run {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Load the model into memory for inference (if downloaded but not loaded).
    /// Uses a shared load task so concurrent callers coalesce (C6 fix).
    func loadModel() async throws {
        guard modelContainer == nil else { return }

        // If already loading, await the existing task
        if let existing = loadTask {
            self.modelContainer = try await existing.value
            return
        }

        guard case .ready = status else { return }

        status = .loading
        let task = Task { @MainActor in
            defer {
                self.loadTask = nil
                // C6 fix: restore status if load failed
                if self.modelContainer == nil {
                    self.status = .ready // still downloaded, just not loaded
                }
            }
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: Self.modelConfiguration
            ) { _ in }
            self.modelContainer = container
            self.status = .ready
            return container
        }
        self.loadTask = task
        self.modelContainer = try await task.value
    }

    /// Unload model from memory (keeps files on disk).
    public func unloadModel() {
        modelContainer = nil
    }

    /// Remove downloaded model files from disk.
    public func removeModel() {
        downloadTask?.cancel()
        downloadTask = nil
        loadTask?.cancel()
        loadTask = nil
        modelContainer = nil

        // Remove from HuggingFace Hub cache
        let hubCache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let modelSlug = Self.modelConfiguration.name.replacingOccurrences(of: "/", with: "--")
        let cachedDir = hubCache.appendingPathComponent("models--\(modelSlug)")
        try? FileManager.default.removeItem(at: cachedDir)

        status = .notDownloaded
        modelSizeBytes = 0
    }

    public var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    public var isModelLoaded: Bool {
        modelContainer != nil
    }

    public var statusDescription: String {
        switch status {
        case .notDownloaded:
            return "Model not downloaded (~\(Self.expectedSizeMB)MB)"
        case .downloading(let progress):
            return "Downloading... \(Int(progress * 100))%"
        case .loading:
            return "Loading model..."
        case .ready where modelContainer != nil:
            let mb = modelSizeBytes / (1024 * 1024)
            return "Qwen2.5-0.5B ready (\(mb)MB)"
        case .ready:
            return "Qwen2.5-0.5B downloaded (not loaded)"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }

    // MARK: - Private

    /// Calculate directory size off-main-actor (C5 fix).
    private nonisolated static func calculateDirectorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
