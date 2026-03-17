import SwiftUI
import AppKit

struct ComposeBox: View {
    let onSend: (String) -> Void
    @State private var text = ""
    @State private var isCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            // Collapse toggle bar
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                        Text("Compose")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Theme.composeChrome)
                }
                .buttonStyle(.borderless)

                Spacer()

                if !isCollapsed {
                    Text("⇧Enter send  ⌃Tab switch")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.composeChrome)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.composeBackground)

            if !isCollapsed {
                Divider()

                HStack(alignment: .bottom, spacing: 6) {
                    ComposeTextEditor(text: $text, onSend: sendText)
                        .frame(minHeight: 28, maxHeight: 100)

                    Button(action: sendText) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(text.isEmpty ? Theme.accentDisabled : Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .disabled(text.isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.composeBackground)
            }
        }
    }

    private func sendText() {
        let input = text
        guard !input.isEmpty else { return }
        // Send each line separately with \r to execute, handling multi-line input
        let lines = input.components(separatedBy: .newlines)
        for line in lines {
            if !line.isEmpty {
                onSend(line + "\r")
            }
        }
        text = ""
    }
}

// MARK: - NSTextView wrapper for Enter=newline, Shift+Enter=send

struct ComposeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let textView = ComposeNSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: 28)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = Theme.composeText
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        let coordinator = context.coordinator
        textView.onShiftEnter = {
            coordinator.onSend()
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSend: onSend)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSend: () -> Void

        init(text: Binding<String>, onSend: @escaping () -> Void) {
            _text = text
            self.onSend = onSend
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

// Custom NSTextView that intercepts Shift+Enter and Ctrl+Tab
final class ComposeNSTextView: NSTextView {
    var onShiftEnter: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Ensure we claim first responder even if the terminal view fights for it
        window?.makeFirstResponder(self)
    }

    // In a bundled .app, key events flow through performKeyEquivalent
    // on the responder chain BEFORE keyDown is called. The app's menu
    // system or SwiftUI internals can consume Shift+Enter at that stage,
    // so we must intercept it here as well.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
            onShiftEnter?()
            return true
        }
        // Ctrl+Tab = cycle focus between panes
        if event.keyCode == 48 && event.modifierFlags.contains(.control) {
            NotificationCenter.default.post(name: .cyclePaneFocus, object: nil,
                                            userInfo: ["source": "compose"])
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Shift+Enter = send (fallback for non-bundled contexts)
        if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
            onShiftEnter?()
            return
        }
        // Ctrl+Tab = cycle focus (fallback)
        if event.keyCode == 48 && event.modifierFlags.contains(.control) {
            NotificationCenter.default.post(name: .cyclePaneFocus, object: nil,
                                            userInfo: ["source": "compose"])
            return
        }
        // Plain Enter = newline (default behavior)
        super.keyDown(with: event)
    }
}

// MARK: - Focus cycling notifications
extension Notification.Name {
    static let cyclePaneFocus = Notification.Name("TermGrid.cyclePaneFocus")
    static let focusNotesPanel = Notification.Name("TermGrid.focusNotesPanel")
}
