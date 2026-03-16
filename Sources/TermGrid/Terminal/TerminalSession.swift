import Foundation
import SwiftTerm

@MainActor
final class TerminalSession {
    let cellID: UUID
    let sessionID: UUID
    let sessionType: SessionType
    let terminalView: LocalProcessTerminalView
    var isRunning: Bool = true

    init(cellID: UUID, workingDirectory: String, sessionType: SessionType = .primary) {
        self.cellID = cellID
        self.sessionID = UUID()
        self.sessionType = sessionType
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.nativeBackgroundColor = Theme.terminalBackground
        terminalView.nativeForegroundColor = Theme.terminalForeground
        terminalView.caretColor = Theme.terminalCursor

        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TERMGRID_CELL_ID=\(cellID.uuidString)")
        env.append("TERMGRID_SESSION_TYPE=\(sessionType.rawValue)")

        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env,
            execName: nil,
            currentDirectory: workingDirectory
        )
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
