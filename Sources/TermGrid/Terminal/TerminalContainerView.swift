import AppKit
import SwiftUI
import SwiftTerm

struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalHostView {
        let hostView = TerminalHostView()
        hostView.attach(session.terminalView)
        return hostView
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        nsView.attach(session.terminalView)
    }

    static func dismantleNSView(_ nsView: TerminalHostView, coordinator: ()) {
        nsView.detachHostedTerminalView()
    }
}

final class TerminalHostView: NSView {
    func attach(_ terminalView: LoggingTerminalView) {
        if terminalView.superview !== self {
            terminalView.removeFromSuperviewWithoutNeedingDisplay()
            subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
            addSubview(terminalView)
            terminalView.frame = bounds
            terminalView.autoresizingMask = [.width, .height]
        }
        terminalView.needsDisplay = true
    }

    func detachHostedTerminalView() {
        subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        subviews.first?.frame = bounds
    }
}
