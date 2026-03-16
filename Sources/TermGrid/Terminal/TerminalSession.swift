import Foundation
import SwiftTerm

@MainActor
final class TerminalSession {
    let cellID: UUID
    let sessionID: UUID
    let terminalView: LocalProcessTerminalView
    var isRunning: Bool = true

    init(cellID: UUID, workingDirectory: String) {
        self.cellID = cellID
        self.sessionID = UUID()
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.nativeBackgroundColor = Theme.terminalBackground
        terminalView.nativeForegroundColor = Theme.terminalForeground
        terminalView.caretColor = Theme.terminalCursor

        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: nil,
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
