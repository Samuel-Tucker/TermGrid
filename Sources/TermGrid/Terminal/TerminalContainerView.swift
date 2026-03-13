import SwiftUI
import SwiftTerm

struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = session.terminalView
        view.processDelegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No-op: session identity changes handled via .id(session.sessionID) in parent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let session: TerminalSession

        init(session: TerminalSession) {
            self.session = session
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                session.isRunning = false
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // No-op
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // No-op
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // No-op
        }
    }
}
