import SwiftUI
import AppKit

enum ComposeSlashSelectionAction: Equatable {
    case accept
    case navigate(Int)
    case dismiss
    case none
}

func composeSlashSelectionAction(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags
) -> ComposeSlashSelectionAction {
    let flags = modifiers.intersection(.deviceIndependentFlagsMask)

    switch keyCode {
    case 48 where !flags.contains(.control):
        return .accept
    case 36 where !flags.contains(.shift):
        return .accept
    case 126:
        return .navigate(-1)
    case 125:
        return .navigate(1)
    case 53:
        return .dismiss
    default:
        return .none
    }
}

struct ComposeBox: View {
    let agentType: AgentType?
    let workingDirectory: String?
    let onSend: (String) -> Void
    @State private var text = ""
    @State private var isCollapsed = false
    @State private var slashCommands: [ComposeSlashCommand] = []
    @State private var slashCommandSelectedIndex = 0

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

                VStack(spacing: 0) {
                    if !slashCommands.isEmpty {
                        SlashCommandPopup(
                            commands: slashCommands,
                            selectedIndex: slashCommandSelectedIndex,
                            onSelect: acceptSlashCommand
                        )
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }

                    HStack(alignment: .bottom, spacing: 6) {
                        ComposeTextEditor(
                            text: $text,
                            slashCommandMode: !slashCommands.isEmpty,
                            onSend: sendText,
                            onSlashNavigate: navigateSlashCommands,
                            onSlashAccept: acceptSelectedSlashCommand,
                            onSlashDismiss: dismissSlashCommands
                        )
                        .frame(minHeight: 28, maxHeight: 100)

                        Button(action: sendText) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(text.isEmpty ? Theme.accentDisabled : Theme.accent)
                        }
                        .buttonStyle(.borderless)
                        .disabled(text.isEmpty)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.composeBackground)
            }
        }
        .onChange(of: text, initial: true) { _, newText in
            refreshSlashCommands(for: newText)
        }
    }

    private func sendText() {
        let input = text
        guard !input.isEmpty else { return }
        onSend(input)
        text = ""
        dismissSlashCommands()
    }

    private func refreshSlashCommands(for newText: String) {
        let suggestions = ComposeSlashCommandCatalog.suggestions(
            for: newText,
            agentType: agentType,
            workingDirectory: workingDirectory
        )
        slashCommands = suggestions
        slashCommandSelectedIndex = min(slashCommandSelectedIndex, max(0, suggestions.count - 1))
    }

    private func navigateSlashCommands(_ delta: Int) {
        guard !slashCommands.isEmpty else { return }
        let maxIndex = slashCommands.count - 1
        slashCommandSelectedIndex = max(0, min(maxIndex, slashCommandSelectedIndex + delta))
    }

    private func acceptSelectedSlashCommand() {
        acceptSlashCommand(slashCommandSelectedIndex)
    }

    private func acceptSlashCommand(_ index: Int) {
        guard index < slashCommands.count else { return }
        slashCommandSelectedIndex = index
        text = ComposeSlashCommandCatalog.apply(slashCommands[index], to: text)
        dismissSlashCommands()
    }

    private func dismissSlashCommands() {
        slashCommands = []
        slashCommandSelectedIndex = 0
    }
}

// MARK: - NSTextView wrapper for Enter=newline, Shift+Enter=send

struct ComposeTextEditor: NSViewRepresentable {
    @Binding var text: String
    let slashCommandMode: Bool
    let onSend: () -> Void
    let onSlashNavigate: (Int) -> Void
    let onSlashAccept: () -> Void
    let onSlashDismiss: () -> Void

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
        textView.onSlashNavigate = { coordinator.onSlashNavigate($0) }
        textView.onSlashAccept = { coordinator.onSlashAccept() }
        textView.onSlashDismiss = { coordinator.onSlashDismiss() }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposeNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.slashCommandMode = slashCommandMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSend: onSend,
            onSlashNavigate: onSlashNavigate,
            onSlashAccept: onSlashAccept,
            onSlashDismiss: onSlashDismiss
        )
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSend: () -> Void
        let onSlashNavigate: (Int) -> Void
        let onSlashAccept: () -> Void
        let onSlashDismiss: () -> Void

        init(
            text: Binding<String>,
            onSend: @escaping () -> Void,
            onSlashNavigate: @escaping (Int) -> Void,
            onSlashAccept: @escaping () -> Void,
            onSlashDismiss: @escaping () -> Void
        ) {
            _text = text
            self.onSend = onSend
            self.onSlashNavigate = onSlashNavigate
            self.onSlashAccept = onSlashAccept
            self.onSlashDismiss = onSlashDismiss
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
    var slashCommandMode: Bool = false
    var onSlashNavigate: ((Int) -> Void)?
    var onSlashAccept: (() -> Void)?
    var onSlashDismiss: (() -> Void)?
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
        if slashCommandMode {
            switch composeSlashSelectionAction(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            case .accept:
                onSlashAccept?()
                return true
            case let .navigate(delta):
                onSlashNavigate?(delta)
                return true
            case .dismiss:
                onSlashDismiss?()
                return true
            case .none:
                break
            }
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
        if slashCommandMode {
            switch composeSlashSelectionAction(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            case .accept:
                onSlashAccept?()
                return
            case let .navigate(delta):
                onSlashNavigate?(delta)
                return
            case .dismiss:
                onSlashDismiss?()
                return
            case .none:
                break
            }
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

        if slashCommandMode {
            switch composeSlashSelectionAction(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            case .accept:
                onSlashAccept?()
                return true
            case let .navigate(delta):
                onSlashNavigate?(delta)
                return true
            case .dismiss:
                onSlashDismiss?()
                return true
            case .none:
                break
            }
        }

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

        if slashCommandMode {
            switch composeSlashSelectionAction(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            case .accept:
                onSlashAccept?()
                return
            case let .navigate(delta):
                onSlashNavigate?(delta)
                return
            case .dismiss:
                onSlashDismiss?()
                return
            case .none:
                break
            }
        }

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
    let slashCommandMode: Bool
    let ghostText: String
    let onSend: () -> Void
    let onDismiss: () -> Void
    let onSlashNavigate: (Int) -> Void
    let onSlashAccept: () -> Void
    let onSlashDismiss: () -> Void
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
        textView.onSlashNavigate = { coordinator.onSlashNavigate($0) }
        textView.onSlashAccept = { coordinator.onSlashAccept() }
        textView.onSlashDismiss = { coordinator.onSlashDismiss() }

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
        textView.slashCommandMode = slashCommandMode
        // Sync ghost text
        if ghostText.isEmpty {
            textView.hideGhostText()
        } else {
            textView.showGhostText(ghostText)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSend: onSend, onDismiss: onDismiss,
                    onSlashNavigate: onSlashNavigate,
                    onSlashAccept: onSlashAccept,
                    onSlashDismiss: onSlashDismiss,
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
        let onSlashNavigate: (Int) -> Void
        let onSlashAccept: () -> Void
        let onSlashDismiss: () -> Void
        let onControlPassthrough: (String) -> Void
        let onHistoryTrigger: () -> Void
        let onHistoryNavigate: (Int) -> Void
        let onHistoryConfirm: () -> Void
        let onHistoryDismiss: () -> Void
        let onGhostAccept: () -> Void
        let onGhostAcceptWord: () -> Void
        let onTextChanged: (String) -> Void

        init(text: Binding<String>, onSend: @escaping () -> Void, onDismiss: @escaping () -> Void,
             onSlashNavigate: @escaping (Int) -> Void,
             onSlashAccept: @escaping () -> Void,
             onSlashDismiss: @escaping () -> Void,
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
            self.onSlashNavigate = onSlashNavigate
            self.onSlashAccept = onSlashAccept
            self.onSlashDismiss = onSlashDismiss
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

struct SlashCommandPopup: View {
    let commands: [ComposeSlashCommand]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            let visible = Array(commands.prefix(6))
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, command in
                HStack(spacing: 8) {
                    Text(command.trigger)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(index == selectedIndex ? Theme.accent : Theme.headerText)

                    Text(command.description.isEmpty ? sourceLabel(for: command.source) : command.description)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.composeChrome)
                        .lineLimit(1)

                    Spacer()

                    if command.source != .builtin {
                        Text(sourceLabel(for: command.source))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.historyTimestamp)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(index == selectedIndex ? Theme.historyRowSelected : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(index) }
            }
        }
        .background(Theme.composeBackground.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Theme.phantomDivider.opacity(0.4), lineWidth: 1)
        )
    }

    private func sourceLabel(for source: ComposeSlashCommand.Source) -> String {
        switch source {
        case .builtin: return "builtin"
        case .project: return "project"
        case .user: return "user"
        }
    }
}

// MARK: - Phantom Compose Overlay View

struct PhantomComposeOverlay: View {
    @Binding var text: String
    let pendingCharacter: String?
    let historyMode: Bool
    let slashCommands: [ComposeSlashCommand]
    let slashCommandSelectedIndex: Int
    let ghostText: String
    let onSend: (String) -> Void
    let onDismiss: () -> Void
    let onSlashNavigate: (Int) -> Void
    let onSlashAccept: () -> Void
    let onSlashDismiss: () -> Void
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

            if !slashCommands.isEmpty {
                SlashCommandPopup(
                    commands: slashCommands,
                    selectedIndex: slashCommandSelectedIndex,
                    onSelect: { index in
                        onSlashNavigate(index - slashCommandSelectedIndex)
                        onSlashAccept()
                    }
                )
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }

            // Hint bar
            HStack(spacing: 12) {
                if !slashCommands.isEmpty {
                    Text("Tab command")
                        .foregroundColor(Theme.accent)
                    Text("↑↓ choose")
                        .foregroundColor(Theme.composeChrome)
                } else if !ghostText.isEmpty {
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
                slashCommandMode: !slashCommands.isEmpty,
                ghostText: ghostText,
                onSend: sendText,
                onDismiss: dismiss,
                onSlashNavigate: onSlashNavigate,
                onSlashAccept: onSlashAccept,
                onSlashDismiss: onSlashDismiss,
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
