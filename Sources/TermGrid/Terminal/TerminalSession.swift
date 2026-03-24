import Foundation
import SwiftTerm
import Observation

@MainActor
@Observable
final class TerminalSession {
    let cellID: UUID
    let sessionID: UUID
    let sessionType: SessionType
    let terminalView: LoggingTerminalView
    var isRunning: Bool = true
    var detectedAgent: AgentType? = nil
    @ObservationIgnored var onNotification: ((PatternMatch) -> Void)? = nil
    @ObservationIgnored private var processStarted = false

    private let shell: String
    private let environment: [String]
    private let workingDirectory: String

    init(cellID: UUID, workingDirectory: String, sessionType: SessionType = .primary,
         environment: [String]? = nil, startImmediately: Bool = true) {
        self.cellID = cellID
        self.sessionID = UUID()
        self.sessionType = sessionType
        self.workingDirectory = workingDirectory
        self.terminalView = LoggingTerminalView(frame: .zero)

        self.shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        var env = environment ?? Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TERMGRID_CELL_ID=\(cellID.uuidString)")
        env.append("TERMGRID_SESSION_TYPE=\(sessionType.rawValue)")
        self.environment = env

        terminalView.nativeBackgroundColor = Theme.terminalBackground
        terminalView.nativeForegroundColor = Theme.terminalForeground
        terminalView.caretColor = Theme.terminalCursor

        // Increase scrollback buffer to 5000 lines (SwiftTerm default is 500)
        terminalView.getTerminal().changeHistorySize(5000)

        terminalView.onPatternMatch = { [weak self] match in
            Task { @MainActor in
                self?.onNotification?(match)
            }
        }

        terminalView.onAgentDetected = { [weak self] agent in
            Task { @MainActor in
                self?.detectedAgent = agent
            }
        }

        if startImmediately {
            start()
        }
    }

    func start() {
        guard !processStarted else { return }
        processStarted = true
        isRunning = true
        // Validate working directory exists, fallback to home
        let fm = FileManager.default
        let dir = fm.fileExists(atPath: workingDirectory) ? workingDirectory
            : fm.homeDirectoryForCurrentUser.path
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: environment,
            execName: nil,
            currentDirectory: dir
        )
    }

    /// Replay raw PTY bytes into the terminal (before start).
    /// This restores the exact visual state including colors, cursor positioning, etc.
    func replayScrollback(_ data: Data) {
        terminalView.replayLog(data)
    }

    /// Get the raw PTY output log for saving to disk.
    func getRawScrollback() -> Data {
        return terminalView.getRawLog()
    }

    func send(_ text: String) {
        guard isRunning else { return }
        terminalView.resetScrollLock()
        terminalView.send(txt: text)
    }

    /// Submit compose text using semantics that match the active terminal target.
    /// Agent prompts should be inserted as one payload and submitted once.
    /// Shell compose preserves the existing command-per-line execution behavior.
    func submitComposeText(_ text: String) {
        let writes = Self.composeWriteChunks(for: text, detectedAgent: detectedAgent)
        guard !writes.isEmpty else { return }
        for chunk in writes {
            send(chunk)
        }
    }

    nonisolated static func composeWriteChunks(for text: String, detectedAgent: AgentType?) -> [String] {
        guard !text.isEmpty else { return [] }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if detectedAgent?.usesFullComposeSubmission == true {
            return [normalized + "\r"]
        }

        return normalized
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { $0 + "\r" }
    }

    /// Get the currently selected text in the terminal (if any).
    func getSelectedText() -> String? {
        return terminalView.getSelection()
    }

    /// Extract the last N lines of terminal output as plain text (for MLX context window).
    func getRecentOutput(lines: Int = 50) -> String {
        let terminal = terminalView.getTerminal()
        let bufferData = terminal.getBufferAsData(kind: .normal)
        guard let raw = String(data: bufferData, encoding: .utf8), !raw.isEmpty else { return "" }
        let stripped = TerminalContentExtractor.stripAnsi(raw)
        let allLines = stripped.components(separatedBy: "\n")
        let recent = allLines.suffix(lines)
        return recent.joined(separator: "\n")
    }

    func kill() {
        if isRunning {
            terminalView.terminate()
            isRunning = false
            detectedAgent = nil
        }
    }
}

extension AgentType {
    var usesFullComposeSubmission: Bool {
        switch self {
        case .claudeCode, .codex, .gemini, .aider:
            return true
        case .unknown:
            return false
        }
    }
}
