import Foundation
import SwiftTerm

@MainActor
final class TerminalSession {
    let cellID: UUID
    let sessionID: UUID
    let sessionType: SessionType
    let terminalView: LocalProcessTerminalView
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
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        self.shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        var env = environment ?? Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TERMGRID_CELL_ID=\(cellID.uuidString)")
        env.append("TERMGRID_SESSION_TYPE=\(sessionType.rawValue)")
        self.environment = env

        terminalView.nativeBackgroundColor = Theme.terminalBackground
        terminalView.nativeForegroundColor = Theme.terminalForeground
        terminalView.caretColor = Theme.terminalCursor

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

    /// Feed scrollback text into the terminal emulator (before start).
    /// Also increases scrollback history to 5000 lines.
    func feedScrollback(_ text: String) {
        // Increase scrollback buffer to 5000 lines (SwiftTerm default is 500)
        let terminal = terminalView.getTerminal()
        terminal.changeHistorySize(5000)

        // Feed restored content
        terminalView.feed(text: text)
        terminalView.feed(text: "\n── restored scrollback ──\n")
    }

    /// Read the current scrollback buffer as text.
    func getScrollbackText() -> String? {
        let terminal = terminalView.getTerminal()
        let data = terminal.getBufferAsData(kind: .normal, encoding: .utf8)
        return String(data: data, encoding: .utf8)
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
