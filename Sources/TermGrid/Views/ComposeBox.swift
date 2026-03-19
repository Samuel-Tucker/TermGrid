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
    // Phantom compose callbacks
    var onEnterSend: (() -> Void)?
    var onEscapeDismiss: (() -> Void)?
    var onControlPassthrough: ((String) -> Void)?  // sends ctrl char to PTY
    var useBlockCursor: Bool = false
    /// When true, Enter=send / Shift+Enter=newline (phantom mode, inverted from classic)
    var phantomMode: Bool = false
    // Compose history callbacks
    var historyMode: Bool = false
    var onHistoryTrigger: (() -> Void)?
    var onHistoryNavigate: ((Int) -> Void)?   // -1 = up, +1 = down
    var onHistoryConfirm: (() -> Void)?
    var onHistoryDismiss: (() -> Void)?
    // Ghost text callbacks
    var onGhostAccept: (() -> Void)?
    var onGhostAcceptWord: (() -> Void)?
    var onTextChanged: ((String) -> Void)?

    // MARK: - Ghost text overlay

    private lazy var ghostOverlay: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = self.font
        field.textColor = Theme.composeText.withAlphaComponent(0.30)
        field.backgroundColor = .clear
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        addSubview(field)
        return field
    }()

    private(set) var ghostVisible: Bool = false

    func showGhostText(_ text: String) {
        guard !text.isEmpty, phantomMode else {
            hideGhostText()
            return
        }
        ghostOverlay.stringValue = text
        ghostOverlay.font = self.font
        repositionGhostOverlay()
        ghostOverlay.isHidden = false
        ghostVisible = true
    }

    func hideGhostText() {
        ghostOverlay.isHidden = true
        ghostOverlay.stringValue = ""
        ghostVisible = false
    }

    private func repositionGhostOverlay() {
        guard let lm = layoutManager, let tc = textContainer else { return }
        let cursorPos = selectedRange().location
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: cursorPos, length: 0), actualCharacterRange: nil)
        let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: max(0, glyphRange.location - 1), length: 1), in: tc)
        let inset = textContainerInset
        let x = cursorPos == 0 ? inset.width : glyphRect.maxX + inset.width
        let y = glyphRect.origin.y + inset.height
        ghostOverlay.frame.origin = NSPoint(x: x, y: y)
        ghostOverlay.sizeToFit()
    }

    /// Current line text at cursor position (for multi-line prediction).
    var cursorLineText: String {
        let text = self.string
        let cursorPos = selectedRange().location
        let nsString = text as NSString
        guard cursorPos <= nsString.length else { return text }
        let lineRange = nsString.lineRange(for: NSRange(location: cursorPos, length: 0))
        return nsString.substring(with: lineRange).trimmingCharacters(in: .newlines)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Ensure we claim first responder even if the terminal view fights for it
        window?.makeFirstResponder(self)
    }

    // MARK: - Block cursor drawing

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard useBlockCursor else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }
        guard flag else { return }
        let charWidth = charWidthAtInsertionPoint()
        let blockRect = NSRect(x: rect.origin.x, y: rect.origin.y,
                               width: max(charWidth, 8), height: rect.height)
        Theme.phantomCursorColor.withAlphaComponent(0.85).setFill()
        blockRect.fill()
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        if useBlockCursor {
            let charWidth = charWidthAtInsertionPoint()
            let wider = NSRect(x: invalidRect.origin.x, y: invalidRect.origin.y,
                               width: max(invalidRect.width, charWidth + 2),
                               height: invalidRect.height)
            super.setNeedsDisplay(wider, avoidAdditionalLayout: flag)
        } else {
            super.setNeedsDisplay(invalidRect, avoidAdditionalLayout: flag)
        }
    }

    private func charWidthAtInsertionPoint() -> CGFloat {
        guard let font = self.font else { return 8 }
        let sample: NSString = "M"
        return sample.size(withAttributes: [.font: font]).width
    }

    // MARK: - Key handling

    // In a bundled .app, key events flow through performKeyEquivalent
    // on the responder chain BEFORE keyDown is called. The app's menu
    // system or SwiftUI internals can consume Shift+Enter at that stage,
    // so we must intercept it here as well.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if phantomMode {
            return handlePhantomKeyEquivalent(with: event)
        }
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
        if phantomMode {
            handlePhantomKeyDown(with: event)
            return
        }
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

    // MARK: - Phantom mode key routing

    private func handlePhantomKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Tab (keyCode 48) without Ctrl = accept ghost text or no-op
        if event.keyCode == 48 && !flags.contains(.control) {
            if ghostVisible {
                onGhostAccept?()
            }
            return true // never insert \t in phantom mode
        }

        // Ctrl+Tab = cycle focus
        if event.keyCode == 48 && flags.contains(.control) {
            NotificationCenter.default.post(name: .cyclePaneFocus, object: nil,
                                            userInfo: ["source": "phantom"])
            return true
        }

        // Ctrl+R = open compose history
        if flags.contains(.control), event.charactersIgnoringModifiers?.lowercased() == "r" {
            onHistoryTrigger?()
            return true
        }

        // Ctrl+C/Z/D/L → passthrough to PTY
        if flags.contains(.control), let chars = event.charactersIgnoringModifiers {
            let ctrlChars: [String: String] = ["c": "\u{03}", "z": "\u{1A}", "d": "\u{04}", "l": "\u{0C}"]
            if let ctrl = ctrlChars[chars.lowercased()] {
                onControlPassthrough?(ctrl)
                return true
            }
        }

        // History mode: intercept navigation keys
        if historyMode {
            // Up arrow (126)
            if event.keyCode == 126 {
                onHistoryNavigate?(-1)
                return true
            }
            // Down arrow (125)
            if event.keyCode == 125 {
                onHistoryNavigate?(1)
                return true
            }
            // Enter = confirm selection (plain or shift)
            if event.keyCode == 36 {
                onHistoryConfirm?()
                return true
            }
            // Escape = dismiss history
            if event.keyCode == 53 {
                onHistoryDismiss?()
                return true
            }
        }

        // Enter (keyCode 36)
        if event.keyCode == 36 {
            if flags.contains(.shift) {
                // Shift+Enter = send
                onEnterSend?()
                return true
            }
            // Plain Enter = newline (default NSTextView behavior)
            return false
        }

        // Escape (keyCode 53)
        if event.keyCode == 53 {
            onEscapeDismiss?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func handlePhantomKeyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Tab = accept full ghost text (fallback for keyDown path)
        if event.keyCode == 48 && !flags.contains(.control) {
            if ghostVisible { onGhostAccept?() }
            return // never insert \t
        }

        // Right Arrow at end of text + ghost visible = accept next word
        if event.keyCode == 124 && ghostVisible {
            let cursorAtEnd = selectedRange().location >= (self.string as NSString).length
            if cursorAtEnd {
                onGhostAcceptWord?()
                return
            }
        }

        // Ctrl+R = open compose history
        if flags.contains(.control), event.charactersIgnoringModifiers?.lowercased() == "r" {
            onHistoryTrigger?()
            return
        }

        // Ctrl+C/Z/D/L → passthrough
        if flags.contains(.control), let chars = event.charactersIgnoringModifiers {
            let ctrlChars: [String: String] = ["c": "\u{03}", "z": "\u{1A}", "d": "\u{04}", "l": "\u{0C}"]
            if let ctrl = ctrlChars[chars.lowercased()] {
                onControlPassthrough?(ctrl)
                return
            }
        }

        // History mode: intercept navigation keys
        if historyMode {
            if event.keyCode == 126 { onHistoryNavigate?(-1); return }
            if event.keyCode == 125 { onHistoryNavigate?(1); return }
            if event.keyCode == 36 { onHistoryConfirm?(); return }
            if event.keyCode == 53 { onHistoryDismiss?(); return }
            // All other keys: pass through to text editing (for fuzzy search)
            super.keyDown(with: event)
            return
        }

        // Up Arrow when compose is empty → open history
        if event.keyCode == 126 && self.string.isEmpty {
            onHistoryTrigger?()
            return
        }

        // Shift+Enter = send
        if event.keyCode == 36 {
            if flags.contains(.shift) {
                onEnterSend?()
            } else {
                // Plain Enter = newline
                super.keyDown(with: event)
            }
            return
        }

        // Escape
        if event.keyCode == 53 {
            onEscapeDismiss?()
            return
        }

        // Everything else → normal editing (arrows, backspace, printable chars)
        // Hide ghost on any typing
        if ghostVisible { hideGhostText() }
        super.keyDown(with: event)
    }

    // MARK: - Text change tracking

    override func didChangeText() {
        super.didChangeText()
        onTextChanged?(self.string)
    }
}

// MARK: - Phantom Compose Text Editor (NSViewRepresentable)

struct PhantomComposeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let pendingCharacter: String?
    let historyMode: Bool
    let ghostText: String
    let onSend: () -> Void
    let onDismiss: () -> Void
    let onControlPassthrough: (String) -> Void
    let onHistoryTrigger: () -> Void
    let onHistoryNavigate: (Int) -> Void
    let onHistoryConfirm: () -> Void
    let onHistoryDismiss: () -> Void
    let onGhostAccept: () -> Void
    let onGhostAcceptWord: () -> Void
    let onTextChanged: (String) -> Void

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
        textView.insertionPointColor = Theme.phantomCursorColor

        // Phantom mode
        textView.useBlockCursor = true
        textView.phantomMode = true
        textView.historyMode = historyMode
        textView.delegate = context.coordinator

        let coordinator = context.coordinator
        textView.onEnterSend = { coordinator.onSend() }
        textView.onEscapeDismiss = { coordinator.onDismiss() }
        textView.onControlPassthrough = { coordinator.onControlPassthrough($0) }
        textView.onHistoryTrigger = { coordinator.onHistoryTrigger() }
        textView.onHistoryNavigate = { coordinator.onHistoryNavigate($0) }
        textView.onHistoryConfirm = { coordinator.onHistoryConfirm() }
        textView.onHistoryDismiss = { coordinator.onHistoryDismiss() }
        textView.onGhostAccept = { coordinator.onGhostAccept() }
        textView.onGhostAcceptWord = { coordinator.onGhostAcceptWord() }
        textView.onTextChanged = { coordinator.onTextChanged($0) }

        scrollView.documentView = textView

        // Inject pending character after becoming first responder
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            if let char = self.pendingCharacter {
                textView.insertText(char, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposeNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.historyMode = historyMode
        // Sync ghost text
        if ghostText.isEmpty {
            textView.hideGhostText()
        } else {
            textView.showGhostText(ghostText)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSend: onSend, onDismiss: onDismiss,
                    onControlPassthrough: onControlPassthrough,
                    onHistoryTrigger: onHistoryTrigger,
                    onHistoryNavigate: onHistoryNavigate,
                    onHistoryConfirm: onHistoryConfirm,
                    onHistoryDismiss: onHistoryDismiss,
                    onGhostAccept: onGhostAccept,
                    onGhostAcceptWord: onGhostAcceptWord,
                    onTextChanged: onTextChanged)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSend: () -> Void
        let onDismiss: () -> Void
        let onControlPassthrough: (String) -> Void
        let onHistoryTrigger: () -> Void
        let onHistoryNavigate: (Int) -> Void
        let onHistoryConfirm: () -> Void
        let onHistoryDismiss: () -> Void
        let onGhostAccept: () -> Void
        let onGhostAcceptWord: () -> Void
        let onTextChanged: (String) -> Void

        init(text: Binding<String>, onSend: @escaping () -> Void, onDismiss: @escaping () -> Void,
             onControlPassthrough: @escaping (String) -> Void,
             onHistoryTrigger: @escaping () -> Void,
             onHistoryNavigate: @escaping (Int) -> Void,
             onHistoryConfirm: @escaping () -> Void,
             onHistoryDismiss: @escaping () -> Void,
             onGhostAccept: @escaping () -> Void,
             onGhostAcceptWord: @escaping () -> Void,
             onTextChanged: @escaping (String) -> Void) {
            _text = text
            self.onSend = onSend
            self.onDismiss = onDismiss
            self.onControlPassthrough = onControlPassthrough
            self.onHistoryTrigger = onHistoryTrigger
            self.onHistoryNavigate = onHistoryNavigate
            self.onHistoryConfirm = onHistoryConfirm
            self.onHistoryDismiss = onHistoryDismiss
            self.onGhostAccept = onGhostAccept
            self.onGhostAcceptWord = onGhostAcceptWord
            self.onTextChanged = onTextChanged
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

// MARK: - Phantom Compose Overlay View

struct PhantomComposeOverlay: View {
    @Binding var text: String
    let pendingCharacter: String?
    let historyMode: Bool
    let ghostText: String
    let onSend: (String) -> Void
    let onDismiss: () -> Void
    let onControlPassthrough: (String) -> Void
    let onHistoryTrigger: () -> Void
    let onHistoryNavigate: (Int) -> Void
    let onHistoryConfirm: () -> Void
    let onHistoryDismiss: () -> Void
    let onGhostAccept: () -> Void
    let onGhostAcceptWord: () -> Void
    let onTextChanged: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 1px amber hairline
            Theme.phantomDivider.frame(height: 1)

            // Inner glow (subtle white gradient at top)
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 1)

            // Hint bar
            HStack(spacing: 12) {
                if !ghostText.isEmpty {
                    Text("Tab accept")
                        .foregroundColor(Theme.accent)
                    Text("→ word")
                        .foregroundColor(Theme.composeChrome)
                }
                Text("\u{21E7}Enter send")
                    .foregroundColor(Theme.composeChrome)
                Text("Esc dismiss")
                    .foregroundColor(Theme.composeChrome)
                Text("\u{2303}R history")
                    .foregroundColor(Theme.composeChrome)
                Spacer()
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)

            // Editor
            PhantomComposeTextEditor(
                text: $text,
                pendingCharacter: pendingCharacter,
                historyMode: historyMode,
                ghostText: ghostText,
                onSend: sendText,
                onDismiss: dismiss,
                onControlPassthrough: onControlPassthrough,
                onHistoryTrigger: onHistoryTrigger,
                onHistoryNavigate: onHistoryNavigate,
                onHistoryConfirm: onHistoryConfirm,
                onHistoryDismiss: onHistoryDismiss,
                onGhostAccept: onGhostAccept,
                onGhostAcceptWord: onGhostAcceptWord,
                onTextChanged: onTextChanged
            )
            .frame(minHeight: 28, maxHeight: 100)
        }
        .background(Theme.composeBackground.opacity(0.92))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: -3)
    }

    private func sendText() {
        let input = text
        guard !input.isEmpty else {
            dismiss()
            return
        }
        onSend(input)
        text = ""
    }

    private func dismiss() {
        // Text is preserved via binding — user can resume editing later
        onDismiss()
    }
}

// MARK: - Focus cycling notifications
extension Notification.Name {
    static let cyclePaneFocus = Notification.Name("TermGrid.cyclePaneFocus")
    static let focusNotesPanel = Notification.Name("TermGrid.focusNotesPanel")
    static let focusGitPanel = Notification.Name("TermGrid.focusGitPanel")
    static let terminalScrollLockChanged = Notification.Name("TermGrid.terminalScrollLockChanged")
}
