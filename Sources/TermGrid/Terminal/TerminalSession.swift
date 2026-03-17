import Foundation
import SwiftTerm

@MainActor
final class TerminalSession {
    let cellID: UUID
    let sessionID: UUID
    let sessionType: SessionType
    let terminalView: LoggingTerminalView
    var isRunning: Bool = true
    private var processStarted = false

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

        if startImmediately {
            start()
        }
    }

    func start() {
        guard !processStarted else { return }
        processStarted = true
        isRunning = true
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: environment,
            execName: nil,
            currentDirectory: workingDirectory
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
        terminalView.send(txt: text)
    }

    func kill() {
        if isRunning {
            terminalView.terminate()
            isRunning = false
        }
    }
}
