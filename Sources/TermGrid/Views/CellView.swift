import SwiftUI
import AppKit
import SwiftTerm

struct CellView: View {
    let cell: Cell
    let session: TerminalSession?
    let splitSession: TerminalSession?
    let splitDirection: SplitDirection?
    let onUpdateLabel: (String) -> Void
    let onUpdateNotes: (String) -> Void
    let onUpdateWorkingDirectory: (String) -> Void
    let onRestartSession: () -> Void
    let onToggleSplit: (SplitDirection) -> Void
    let onRestartSplitSession: () -> Void
    let onUpdateTerminalLabel: (String) -> Void
    let onUpdateSplitTerminalLabel: (String) -> Void
    let onUpdateExplorerDirectory: (String) -> Void
    let onUpdateExplorerViewMode: (ExplorerViewMode) -> Void

    @State private var isEditingLabel = false
    @State private var labelDraft = ""
    @State private var showNotes = true
    @State private var showExplorer = false
    @State private var hoveredHeaderButton: String? = nil
    @State private var focusMonitor: Any? = nil
    @FocusState private var labelFieldFocused: Bool

    private static let headerButtonIDs = ["splitH", "splitV", "explorer", "notes"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — not clipped so hover tooltips can overflow
            headerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.headerBackground)
                .zIndex(1)

            Theme.divider.frame(height: 1)

            // Body: terminal/explorer + optional notes panel
            HStack(spacing: 0) {
                cellBody
                if showNotes {
                    Divider()
                    NotesView(notes: cell.notes, onUpdate: onUpdateNotes)
                        .frame(width: 160)
                }
            }
            .clipped()
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.cellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.cellBorder, lineWidth: 1)
        )
        .onAppear {
            // Ctrl+Tab local event monitor for focus cycling
            focusMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // keyCode 48 = Tab
                if event.keyCode == 48 && event.modifierFlags.contains(.control) {
                    cycleFocus()
                    return nil // consume the event
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = focusMonitor {
                NSEvent.removeMonitor(monitor)
                focusMonitor = nil
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack {
            if isEditingLabel {
                TextField("Untitled", text: $labelDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                    .focused($labelFieldFocused)
                    .onSubmit { commitLabel() }
                    .onKeyPress(.escape) {
                        cancelLabel()
                        return .handled
                    }
                    .onChange(of: labelFieldFocused) { _, focused in
                        if !focused && isEditingLabel { commitLabel() }
                    }
                    .onAppear {
                        labelDraft = cell.label
                        labelFieldFocused = true
                    }
            } else {
                Text(cell.label.isEmpty ? "Untitled" : cell.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(cell.label.isEmpty ? Theme.headerIcon : Theme.headerText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        labelDraft = cell.label
                        isEditingLabel = true
                    }
            }

            // Repo pill badge — doubles as directory Menu
            if let badgePath = effectiveExplorerPath, badgePath != FileManager.default.homeDirectoryForCurrentUser.path {
                Menu {
                    Button("Set Terminal Directory") { pickWorkingDirectory() }
                    Button("Set Explorer Directory") { pickExplorerDirectory() }
                    Divider()
                    Button(showExplorer ? "Show Terminal" : "Show Explorer") {
                        withAnimation(.easeInOut(duration: 0.4)) { showExplorer.toggle() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                        Text(shortenPath(badgePath))
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.cellBorder))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                // No directory set yet — show small folder icon as Menu
                Menu {
                    Button("Set Terminal Directory") { pickWorkingDirectory() }
                    Button("Set Explorer Directory") { pickExplorerDirectory() }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.headerIcon)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

            // Header icon buttons with Dock-style hover magnification
            headerIconButton(
                id: "splitH",
                systemName: splitDirection == .horizontal ? "square.split.1x2.fill" : "square.split.1x2",
                label: splitDirection == .horizontal ? "Close split" : "Split horizontal",
                action: { onToggleSplit(.horizontal) }
            )

            headerIconButton(
                id: "splitV",
                systemName: splitDirection == .vertical ? "square.split.2x1.fill" : "square.split.2x1",
                label: splitDirection == .vertical ? "Close split" : "Split vertical",
                action: { onToggleSplit(.vertical) }
            )

            headerIconButton(
                id: "explorer",
                systemName: showExplorer ? "terminal" : "doc.text.magnifyingglass",
                label: showExplorer ? "Show terminal" : "Show explorer",
                action: {
                    withAnimation(.easeInOut(duration: 0.4)) { showExplorer.toggle() }
                }
            )

            headerIconButton(
                id: "notes",
                systemName: showNotes ? "note.text" : "note.text.badge.plus",
                label: showNotes ? "Hide notes" : "Show notes",
                action: { showNotes.toggle() }
            )
        }
    }

    // MARK: - Dock-Style Hover Button

    @ViewBuilder
    private func headerIconButton(
        id: String,
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredHeaderButton == id
        let isAnyHovered = hoveredHeaderButton != nil
        let neighbor = isNeighbor(id, to: hoveredHeaderButton)

        let scale: CGFloat = isHovered ? 1.35 : (neighbor ? 1.12 : 1.0)
        let blurRadius: CGFloat = isHovered ? 0 : (isAnyHovered ? (neighbor ? 0.5 : 1.5) : 0)
        let iconColor = isHovered ? Theme.accent : Theme.headerIcon

        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(iconColor)
        }
        .buttonStyle(.borderless)
        .scaleEffect(scale)
        .blur(radius: blurRadius)
        .zIndex(isHovered ? 1 : 0)
        .overlay(alignment: .top) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Theme.headerText)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.cellBackground)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: -2)
                )
                .offset(y: isHovered ? -24 : -16)
                .opacity(isHovered ? 1 : 0)
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                hoveredHeaderButton = hovering ? id : nil
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hoveredHeaderButton)
    }

    private func isNeighbor(_ id: String, to targetID: String?) -> Bool {
        guard let targetID,
              let targetIdx = Self.headerButtonIDs.firstIndex(of: targetID),
              let currentIdx = Self.headerButtonIDs.firstIndex(of: id) else { return false }
        return abs(targetIdx - currentIdx) == 1
    }

    // MARK: - Cell Body (page flip between terminal and explorer)

    @ViewBuilder
    private var cellBody: some View {
        ZStack {
            terminalBody
                .opacity(showExplorer ? 0 : 1)
                .rotation3DEffect(
                    .degrees(showExplorer ? -90 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )

            FileExplorerView(
                rootPath: cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory,
                viewMode: cell.explorerViewMode,
                onViewModeChange: onUpdateExplorerViewMode
            )
            .opacity(showExplorer ? 1 : 0)
            .rotation3DEffect(
                .degrees(showExplorer ? 0 : 90),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
        }
        .animation(.easeInOut(duration: 0.4), value: showExplorer)
    }

    // MARK: - Terminal Body

    @ViewBuilder
    private var terminalBody: some View {
        if splitSession != nil, let dir = splitDirection {
            splitContainer(direction: dir) {
                labeledTerminalPane(
                    session: session,
                    label: cell.terminalLabel,
                    placeholder: "Label terminal...",
                    onRestart: onRestartSession,
                    onUpdateLabel: onUpdateTerminalLabel
                )
                Divider()
                labeledTerminalPane(
                    session: splitSession,
                    label: cell.splitTerminalLabel,
                    placeholder: "Label terminal...",
                    onRestart: onRestartSplitSession,
                    onUpdateLabel: onUpdateSplitTerminalLabel
                )
            }
        } else {
            labeledTerminalPane(
                session: session,
                label: cell.terminalLabel,
                placeholder: "Label terminal...",
                onRestart: onRestartSession,
                onUpdateLabel: onUpdateTerminalLabel
            )
        }
    }

    @ViewBuilder
    private func splitContainer<Content: View>(direction: SplitDirection, @ViewBuilder content: () -> Content) -> some View {
        switch direction {
        case .horizontal:
            VStack(spacing: 0) { content() }
        case .vertical:
            HStack(spacing: 0) { content() }
        }
    }

    @ViewBuilder
    private func labeledTerminalPane(
        session: TerminalSession?,
        label: String,
        placeholder: String,
        onRestart: @escaping () -> Void,
        onUpdateLabel: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            TerminalLabelBar(label: label, placeholder: placeholder, onCommit: onUpdateLabel)
            terminalPane(session: session, onRestart: onRestart)
        }
    }

    @ViewBuilder
    private func terminalPane(session: TerminalSession?, onRestart: @escaping () -> Void) -> some View {
        if let session {
            VStack(spacing: 0) {
                ZStack {
                    TerminalContainerView(session: session)
                        .id(session.sessionID)

                    if !session.isRunning {
                        VStack(spacing: 8) {
                            Text("Session ended")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.overlayText)
                            Button("Restart", action: onRestart)
                                .buttonStyle(.bordered)
                                .tint(Theme.accent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.cellBackground.opacity(0.85))
                    }
                }

                ComposeBox { text in
                    session.send(text)
                }
            }
        } else {
            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Starting terminal...")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.composePlaceholder)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.cellBackground)
        }
    }

    // MARK: - Helpers

    private var effectiveExplorerPath: String? {
        let path = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
        return path.isEmpty ? nil : path
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Actions

    private func commitLabel() {
        isEditingLabel = false
        if labelDraft != cell.label {
            onUpdateLabel(labelDraft)
        }
    }

    private func cancelLabel() {
        isEditingLabel = false
    }

    private func pickWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: cell.workingDirectory)
        panel.prompt = "Select"
        panel.message = "Choose a working directory for this terminal"

        if panel.runModal() == .OK, let url = panel.url {
            onUpdateWorkingDirectory(url.path)
        }
    }

    private func pickExplorerDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let effectiveDir = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
        panel.directoryURL = URL(fileURLWithPath: effectiveDir)
        panel.prompt = "Select"
        panel.message = "Choose a directory for the file explorer"
        if panel.runModal() == .OK, let url = panel.url {
            onUpdateExplorerDirectory(url.path)
        }
    }

    // MARK: - Focus Cycling (Ctrl+Tab)

    /// Find the nearest common ancestor cell container for the current responder.
    /// We walk up from the first responder to find an NSHostingView-level container,
    /// then scope all focus searches within that subtree so each cell is independent.
    private func cellContainer(for responder: NSResponder?) -> NSView? {
        var view = responder as? NSView ?? (responder as? NSTextView)
        while let v = view {
            // SwiftUI hosts each cell in an NSHostingView — find the one that contains
            // both a terminal view and a compose view (i.e., it's a cell, not the whole window)
            if findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: v) != nil,
               findView(ofType: ComposeNSTextView.self, in: v) != nil {
                return v
            }
            view = v.superview
        }
        return nil
    }

    private func cycleFocus() {
        guard let window = NSApp.keyWindow else { return }
        let currentResponder = window.firstResponder

        // Scope search to the current cell's view subtree
        let container = cellContainer(for: currentResponder) ?? window.contentView

        // Determine current focus: terminal, compose, or notes
        let isTerminal = currentResponder is SwiftTerm.TerminalView
            || (currentResponder?.isKind(of: NSClassFromString("SwiftTerm.TerminalView") ?? NSView.self) ?? false)
        let isCompose = currentResponder is ComposeNSTextView

        if isTerminal {
            // Terminal → Compose: find the ComposeNSTextView in THIS cell
            if let compose = findView(ofType: ComposeNSTextView.self, in: container) {
                window.makeFirstResponder(compose)
            }
        } else if isCompose {
            if showNotes {
                // Compose → Notes
                NotificationCenter.default.post(name: .focusNotesPanel, object: cell.id)
            } else {
                // Compose → Terminal (notes hidden)
                if let term = findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: container) {
                    window.makeFirstResponder(term)
                }
            }
        } else {
            // Notes or other → Terminal
            if let term = findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: container) {
                window.makeFirstResponder(term)
            }
        }
    }

    private func findView<T: NSView>(ofType type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = findView(ofType: type, in: subview) {
                return found
            }
        }
        return nil
    }
}
