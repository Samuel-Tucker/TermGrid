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
    let onCloseCell: () -> Void
    let composeHistory: [ComposeHistoryEntry]
    let onAddToComposeHistory: (String) -> Void
    let uiState: CellUIState
    let notificationState: CellNotificationState
    let completionEngine: CompletionEngine
    var showDragHandle: Bool = false
    var onDragChanged: (CGSize) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    @State private var isEditingLabel = false
    @State private var labelDraft = ""
    @State private var hoveredHeaderButton: String? = nil
    @State private var isDragHandleHovered = false
    @State private var showCloseConfirmation = false
    @State private var focusMonitor: Any? = nil
    @State private var gitModel = GitStatusModel()
    @State private var previewingFile: String? = nil
    @FocusState private var labelFieldFocused: Bool

    private static let headerButtonIDs = ["splitH", "splitV", "folder", "explorer", "git", "notes"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — not clipped so hover tooltips can overflow
            headerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.headerBackground)
                .zIndex(1)

            Theme.divider.frame(height: 1)

            // Close confirmation bar
            if showCloseConfirmation {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: 4)
                        .padding(.vertical, 4)

                    Text("Close this terminal?")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.headerText)
                        .padding(.leading, 10)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCloseConfirmation = false
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.headerText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Theme.cellBorder)
                            )
                    }
                    .buttonStyle(.borderless)

                    Button {
                        onCloseCell()
                    } label: {
                        Text("Close")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Theme.accent)
                            )
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.headerBackground)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Body: optional git sidebar + terminal/explorer + optional notes panel
            HStack(spacing: 0) {
                if uiState.showGit {
                    GitSidebarView(
                        cellID: cell.id,
                        model: gitModel,
                        onFileClick: { path in
                            let dir = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
                            let fullPath = path.hasPrefix("/") ? path : (dir as NSString).appendingPathComponent(path)
                            previewingFile = fullPath
                            if uiState.bodyMode != .explorer {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    uiState.bodyMode = .explorer
                                }
                            }
                        }
                    )
                    .frame(width: 160)
                    Divider()
                }
                cellBody
                if uiState.scratchPadVisible {
                    Divider()
                    NotesView(
                        cellID: cell.id,
                        notes: cell.notes,
                        onUpdate: onUpdateNotes,
                        onSendToTerminal: { text in
                            session?.send(text)
                        }
                    )
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
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(notificationDotColor, lineWidth: 2)
                .opacity(notificationState.showBorderPulse ? 1 : 0)
                .animation(.easeInOut(duration: 1.5).repeatCount(2, autoreverses: true), value: notificationState.showBorderPulse)
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
            gitModel.stopPolling()
        }
        .onChange(of: completionEngine.predictions) { _, predictions in
            guard uiState.phantomComposeActive, uiState.ghostEnabled,
                  !uiState.composeHistoryActive else {
                uiState.ghostText = ""
                return
            }
            if let best = predictions.first {
                let (_, partial) = Tokenizer.extractPartial(uiState.phantomComposeText)
                if !partial.isEmpty, best.text.lowercased().hasPrefix(partial.lowercased()) {
                    // Show the rest of the word as ghost
                    uiState.ghostText = String(best.text.dropFirst(partial.count))
                    uiState.ghostFullToken = best.text
                } else if partial.isEmpty {
                    uiState.ghostText = best.text
                    uiState.ghostFullToken = best.text
                } else {
                    uiState.ghostText = ""
                    uiState.ghostFullToken = ""
                }
            } else {
                uiState.ghostText = ""
                uiState.ghostFullToken = ""
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack {
            // Drag handle with glass morphism hover
            if showDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isDragHandleHovered ? Theme.accent : Theme.headerIcon)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.ultraThinMaterial)
                            .opacity(isDragHandleHovered ? 1 : 0)
                    )
                    .scaleEffect(isDragHandleHovered ? 1.35 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isDragHandleHovered)
                    .contentShape(Rectangle())
                    .onHover { isDragHandleHovered = $0 }
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in onDragChanged(value.translation) }
                            .onEnded { _ in onDragEnded() }
                    )
                    .tooltip("Drag to reorder")
            }

            // Notification dot
            if notificationState.severity != nil {
                Circle()
                    .fill(notificationDotColor)
                    .frame(width: 6, height: 6)
            }

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

            // Split buttons — next to label for quick access
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

            // Repo pill badge — doubles as directory Menu (dock-style hover)
            if let badgePath = effectiveExplorerPath, badgePath != FileManager.default.homeDirectoryForCurrentUser.path {
                folderPillMenu(path: badgePath)
            } else {
                // No directory set — plain folder icon with dock hover
                headerMenuButton(id: "folder", systemName: "folder", label: "Set directory") {
                    Button("Set Both Directories") { pickBothDirectories() }
                    Divider()
                    Button("Set Terminal Directory") { pickWorkingDirectory() }
                    Button("Set Explorer Directory") { pickExplorerDirectory() }
                }
            }

            Spacer()

            // Header icon buttons with Dock-style hover magnification
            headerIconButton(
                id: "explorer",
                systemName: uiState.bodyMode == .explorer ? "terminal" : "doc.text.magnifyingglass",
                label: uiState.bodyMode == .explorer ? "Show terminal" : "Show explorer",
                action: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        uiState.bodyMode = uiState.bodyMode == .explorer ? .terminal : .explorer
                    }
                }
            )

            headerIconButton(
                id: "git",
                systemName: "arrow.triangle.branch",
                label: uiState.showGit ? "Hide git" : "Show git",
                action: {
                    uiState.showGit.toggle()
                    if uiState.showGit {
                        let dir = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
                        gitModel.setDirectory(dir)
                        gitModel.startPolling()
                    } else {
                        gitModel.stopPolling()
                    }
                }
            )

            headerMenuButton(id: "notes", systemName: notesIcon, label: "Notes") {
                Button("Scratch Pad") { uiState.scratchPadVisible.toggle() }
                Button(uiState.bodyMode == .projectNotes ? "Close Project Notes" : "Project Notes") {
                    uiState.bodyMode = uiState.bodyMode == .projectNotes ? .terminal : .projectNotes
                }
                Divider()
                Button("Hide All") {
                    uiState.scratchPadVisible = false
                    if uiState.bodyMode == .projectNotes { uiState.bodyMode = .terminal }
                }
            }

            // Gap separator before destructive action
            Spacer().frame(width: 8)

            // Close button — always orange, not part of dock neighbor magnification
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCloseConfirmation = true
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .scaleEffect(hoveredHeaderButton == "close" ? 1.35 : 1.0)
            .tooltip("Close terminal")
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    hoveredHeaderButton = hovering ? "close" : nil
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hoveredHeaderButton)
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
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .blur(radius: blurRadius)
        .zIndex(isHovered ? 1 : 0)
        .tooltip(label)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                hoveredHeaderButton = hovering ? id : nil
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hoveredHeaderButton)
    }

    private var notesIcon: String {
        if uiState.bodyMode == .projectNotes || uiState.scratchPadVisible {
            return "note.text"
        }
        return "note.text.badge.plus"
    }

    @ViewBuilder
    private func headerMenuButton<Content: View>(
        id: String,
        systemName: String,
        label: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isHovered = hoveredHeaderButton == id
        let isAnyHovered = hoveredHeaderButton != nil
        let neighbor = isNeighbor(id, to: hoveredHeaderButton)

        let scale: CGFloat = isHovered ? 1.35 : (neighbor ? 1.12 : 1.0)
        let blurRadius: CGFloat = isHovered ? 0 : (isAnyHovered ? (neighbor ? 0.5 : 1.5) : 0)
        let iconColor = isHovered ? Theme.accent : Theme.headerIcon

        Menu {
            content()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(iconColor)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .scaleEffect(scale)
        .blur(radius: blurRadius)
        .zIndex(isHovered ? 1 : 0)
        .tooltip(label)
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

    // MARK: - Folder Pill Menu (dock-style hover, icon scales, text stays crisp)

    @ViewBuilder
    private func folderPillMenu(path: String) -> some View {
        let isHovered = hoveredHeaderButton == "folder"
        let isAnyHovered = hoveredHeaderButton != nil
        let neighbor = isNeighbor("folder", to: hoveredHeaderButton)
        let iconScale: CGFloat = isHovered ? 1.35 : (neighbor ? 1.12 : 1.0)
        let blurRadius: CGFloat = isHovered ? 0 : (isAnyHovered ? (neighbor ? 0.5 : 1.5) : 0)

        Menu {
            Button("Set Both Directories") { pickBothDirectories() }
            Divider()
            Button("Set Terminal Directory") { pickWorkingDirectory() }
            Button("Set Explorer Directory") { pickExplorerDirectory() }
            Divider()
            Button(uiState.bodyMode == .explorer ? "Show Terminal" : "Show Explorer") {
                withAnimation(.easeInOut(duration: 0.4)) {
                    uiState.bodyMode = uiState.bodyMode == .explorer ? .terminal : .explorer
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 8))
                    .scaleEffect(iconScale)
                Text(shortenPath(path))
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundColor(isHovered ? Theme.accent : Theme.accent.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.cellBorder))
            .blur(radius: blurRadius)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .zIndex(isHovered ? 1 : 0)
        .tooltip("Directory")
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                hoveredHeaderButton = hovering ? "folder" : nil
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hoveredHeaderButton)
    }

    // MARK: - Cell Body (page flip between terminal and explorer)

    private var effectiveDir: String {
        let path = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
        return path
    }

    @ViewBuilder
    private var cellBody: some View {
        switch uiState.bodyMode {
        case .terminal:
            terminalBody
                .transition(.opacity)
        case .explorer:
            FileExplorerView(
                cellID: cell.id,
                rootPath: effectiveDir,
                viewMode: cell.explorerViewMode,
                previewingFile: $previewingFile,
                onViewModeChange: onUpdateExplorerViewMode
            )
            .transition(.opacity)
        case .projectNotes:
            ProjectNotesView(
                cellID: cell.id,
                effectiveDirectory: effectiveDir,
                onChooseDirectory: { pickBothDirectories() },
                onSendToTerminal: { text in session?.send(text) }
            )
            .transition(.opacity)
        }
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
                    onUpdateLabel: onUpdateTerminalLabel,
                    paneState: uiState.primaryPane
                )
                Divider()
                labeledTerminalPane(
                    session: splitSession,
                    label: cell.splitTerminalLabel,
                    placeholder: "Label terminal...",
                    onRestart: onRestartSplitSession,
                    onUpdateLabel: onUpdateSplitTerminalLabel,
                    paneState: uiState.splitPane
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
        onUpdateLabel: @escaping (String) -> Void,
        paneState: PaneComposeState? = nil
    ) -> some View {
        VStack(spacing: 0) {
            TerminalLabelBar(
                label: label,
                placeholder: placeholder,
                agentType: session?.detectedAgent,
                onCommit: onUpdateLabel
            )
            terminalPane(session: session, onRestart: onRestart, paneState: paneState ?? uiState.primaryPane)
        }
    }

    @ViewBuilder
    private func terminalPane(session: TerminalSession?, onRestart: @escaping () -> Void, paneState: PaneComposeState) -> some View {
        if let session {
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
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

                        // Agent work shutter
                        if uiState.shutterEnabled && notificationState.agentBusy {
                            VStack(spacing: 12) {
                                Image(systemName: "gearshape.2")
                                    .font(.system(size: 28))
                                    .foregroundColor(Theme.accent)
                                    .symbolEffect(.pulse, isActive: true)
                                Text(notificationState.agentName.isEmpty
                                     ? "Agent at work..."
                                     : "\(notificationState.agentName) at work...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.overlayText)
                                Text("Terminal will reappear when done")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.composePlaceholder)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.cellBackground.opacity(0.92))
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }

                        // Dim overlay when phantom compose is active
                        if uiState.phantomComposeEnabled && paneState.phantomComposeActive {
                            Color.black.opacity(0.15)
                                .allowsHitTesting(false)
                        }
                    }

                    // Phantom compose overlay — inside the ZStack, pinned to bottom
                    if uiState.phantomComposeEnabled && paneState.phantomComposeActive {
                        VStack(spacing: 0) {
                            // History popup (grows upward above compose)
                            if paneState.composeHistoryActive {
                                ComposeHistoryPopup(
                                    history: composeHistory,
                                    query: paneState.phantomComposeText,
                                    selectedIndex: paneState.composeHistorySelectedIndex,
                                    onSelect: { content in
                                        paneState.phantomComposeText = content
                                        paneState.composeHistoryActive = false
                                        paneState.composeHistorySelectedIndex = 0
                                    },
                                    onDismiss: {
                                        paneState.composeHistoryActive = false
                                        paneState.composeHistorySelectedIndex = 0
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            PhantomComposeOverlay(
                                text: Binding(
                                    get: { paneState.phantomComposeText },
                                    set: { paneState.phantomComposeText = $0 }
                                ),
                                pendingCharacter: paneState.phantomPendingCharacter,
                                historyMode: paneState.composeHistoryActive,
                                ghostText: (uiState.ghostEnabled && !paneState.composeHistoryActive) ? paneState.ghostText : "",
                                onSend: { text in
                                    // Save to history
                                    onAddToComposeHistory(text)
                                    // Learn from sent command
                                    completionEngine.recordCommand(text, acceptedSuggestion: paneState.ghostAccepted)
                                    paneState.ghostAccepted = false
                                    // Send text then \r separately so terminal processes the execute
                                    let lines = text.components(separatedBy: .newlines)
                                        .filter { !$0.isEmpty }
                                    if lines.count == 1 {
                                        session.send(lines[0])
                                        session.send("\r")
                                    } else {
                                        // Multi-line: send each with \r, small delay between
                                        for (i, line) in lines.enumerated() {
                                            let delay = Double(i) * 0.05
                                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                                session.send(line + "\r")
                                            }
                                        }
                                    }
                                    // Dismiss compose
                                    paneState.phantomComposeActive = false
                                    paneState.phantomPendingCharacter = nil
                                    paneState.ghostText = ""
                                    paneState.ghostFullToken = ""
                                    paneState.composeHistoryActive = false
                                    paneState.composeHistorySelectedIndex = 0
                                    // Return focus to terminal
                                    returnFocusToTerminal()
                                },
                                onDismiss: {
                                    paneState.phantomComposeActive = false
                                    paneState.phantomPendingCharacter = nil
                                    paneState.ghostText = ""
                                    paneState.ghostFullToken = ""
                                    paneState.ghostAccepted = false
                                    paneState.composeHistoryActive = false
                                    paneState.composeHistorySelectedIndex = 0
                                    returnFocusToTerminal()
                                },
                                onControlPassthrough: { ctrlChar in
                                    session.send(ctrlChar)
                                },
                                onHistoryTrigger: {
                                    guard !composeHistory.isEmpty else { return }
                                    paneState.composeHistoryActive = true
                                    paneState.composeHistorySelectedIndex = 0
                                },
                                onHistoryNavigate: { delta in
                                    let filtered = filteredHistoryCount(for: paneState)
                                    guard filtered > 0 else { return }
                                    let maxIdx = min(filtered, 5) - 1
                                    paneState.composeHistorySelectedIndex = max(0, min(maxIdx, paneState.composeHistorySelectedIndex + delta))
                                },
                                onHistoryConfirm: {
                                    let entries = filteredHistory(for: paneState)
                                    let visible = Array(entries.prefix(5))
                                    if paneState.composeHistorySelectedIndex < visible.count {
                                        paneState.phantomComposeText = visible[paneState.composeHistorySelectedIndex].content
                                    }
                                    paneState.composeHistoryActive = false
                                    paneState.composeHistorySelectedIndex = 0
                                },
                                onHistoryDismiss: {
                                    paneState.composeHistoryActive = false
                                    paneState.composeHistorySelectedIndex = 0
                                },
                                onGhostAccept: {
                                    // Accept full ghost suggestion
                                    let ghost = paneState.ghostText
                                    let fullToken = paneState.ghostFullToken
                                    guard !ghost.isEmpty else { return }
                                    let inputBefore = paneState.phantomComposeText
                                    let (_, partial) = Tokenizer.extractPartial(inputBefore)
                                    if !partial.isEmpty && ghost.hasPrefix(partial) {
                                        let suffix = String(ghost.dropFirst(partial.count))
                                        paneState.phantomComposeText += suffix
                                    } else {
                                        paneState.phantomComposeText += (inputBefore.last == " " ? "" : " ") + ghost
                                    }
                                    // Boost confidence using the FULL token (C4 fix)
                                    completionEngine.recordAcceptance(input: inputBefore, acceptedSuggestion: fullToken)
                                    paneState.ghostText = ""
                                    paneState.ghostFullToken = ""
                                    paneState.ghostAccepted = true
                                    // Don't recordCommand here — happens on send (C3 fix)
                                },
                                onGhostAcceptWord: {
                                    // Accept first word of ghost
                                    let ghost = paneState.ghostText
                                    guard !ghost.isEmpty else { return }
                                    let word = ghost.prefix(while: { !$0.isWhitespace })
                                    let (_, partial) = Tokenizer.extractPartial(paneState.phantomComposeText)
                                    if !partial.isEmpty && ghost.hasPrefix(partial) {
                                        let suffix = String(word.dropFirst(partial.count))
                                        paneState.phantomComposeText += suffix
                                    } else {
                                        paneState.phantomComposeText += (paneState.phantomComposeText.last == " " ? "" : " ") + word
                                    }
                                    // Re-request predictions for updated text
                                    completionEngine.requestPredictions(for: paneState.phantomComposeText)
                                },
                                onTextChanged: { newText in
                                    let previousGhost = paneState.ghostText
                                    let previousFullToken = paneState.ghostFullToken
                                    paneState.ghostText = ""
                                    paneState.ghostFullToken = ""
                                    // Only penalize if user DIVERGED from the ghost (C1 fix)
                                    // If the typed char continues the ghost prefix, it's not a rejection
                                    if !previousGhost.isEmpty && !previousFullToken.isEmpty {
                                        let (_, newPartial) = Tokenizer.extractPartial(newText)
                                        let isContin = !newPartial.isEmpty
                                            && previousFullToken.lowercased().hasPrefix(newPartial.lowercased())
                                        if !isContin {
                                            completionEngine.recordRejection(
                                                input: newText, rejectedSuggestion: previousFullToken
                                            )
                                        }
                                    }
                                    guard uiState.ghostEnabled, !paneState.composeHistoryActive else { return }
                                    completionEngine.requestPredictions(for: newText)
                                }
                            )
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8)),
                            removal: .opacity
                                .animation(.easeIn(duration: 0.15))
                        ))
                    }
                }

                // Classic ComposeBox — only when phantom is disabled
                if !uiState.phantomComposeEnabled {
                    ComposeBox { text in
                        session.send(text)
                    }
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

    // MARK: - Notification

    private var notificationDotColor: SwiftUI.Color {
        switch notificationState.severity {
        case .success: return Theme.staged
        case .error: return Theme.error
        case .attention: return Theme.accent
        case .none: return .clear
        }
    }

    // MARK: - Phantom Compose Helpers

    private func returnFocusToTerminal() {
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow {
                let container = cellContainer(for: window.firstResponder) ?? window.contentView
                if let term = findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: container) {
                    window.makeFirstResponder(term)
                }
            }
        }
    }

    private func filteredHistory(for pane: PaneComposeState? = nil) -> [ComposeHistoryEntry] {
        let reversed = composeHistory.reversed()
        let query = (pane ?? uiState.primaryPane).phantomComposeText
        if query.isEmpty { return Array(reversed) }
        return reversed.filter { fuzzyMatch(query: query, in: $0.content) != nil }
    }

    private func filteredHistoryCount(for pane: PaneComposeState? = nil) -> Int {
        filteredHistory(for: pane).count
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
            autoFillLabelIfEmpty(from: url)
        }
    }

    private func pickBothDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: cell.workingDirectory)
        panel.prompt = "Select"
        panel.message = "Choose a directory for both terminal and explorer"
        if panel.runModal() == .OK, let url = panel.url {
            onUpdateWorkingDirectory(url.path)
            onUpdateExplorerDirectory(url.path)
            autoFillLabelIfEmpty(from: url)
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
            autoFillLabelIfEmpty(from: url)
        }
    }

    private func autoFillLabelIfEmpty(from url: URL) {
        let name = url.lastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard cell.label.isEmpty,
              url != home,
              url.path != "/" else { return }
        onUpdateLabel(name)
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
        let container = cellContainer(for: currentResponder) ?? window.contentView

        // If phantom compose is active on either pane, dismiss it and return to terminal
        let activePane: PaneComposeState? =
            uiState.primaryPane.phantomComposeActive ? uiState.primaryPane :
            uiState.splitPane.phantomComposeActive ? uiState.splitPane : nil
        if let pane = activePane {
            pane.phantomComposeActive = false
            pane.phantomPendingCharacter = nil
            if let term = findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: container) {
                window.makeFirstResponder(term)
            }
            return
        }

        let isTerminal = currentResponder is SwiftTerm.TerminalView
            || (currentResponder?.isKind(of: NSClassFromString("SwiftTerm.TerminalView") ?? NSView.self) ?? false)
        let isCompose = currentResponder is ComposeNSTextView

        if isTerminal {
            // Terminal → Compose (classic mode) or Git/Notes
            if !uiState.phantomComposeEnabled {
                if let compose = findView(ofType: ComposeNSTextView.self, in: container) {
                    window.makeFirstResponder(compose)
                    return
                }
            }
            // Phantom mode: skip compose, go to git/notes/terminal
            if uiState.showGit {
                NotificationCenter.default.post(name: .focusGitPanel, object: cell.id)
            } else if uiState.scratchPadVisible {
                NotificationCenter.default.post(name: .focusNotesPanel, object: cell.id)
            }
        } else if isCompose {
            // Compose → Git (if visible) → Notes (if visible) → Terminal
            if uiState.showGit {
                NotificationCenter.default.post(name: .focusGitPanel, object: cell.id)
            } else if uiState.scratchPadVisible {
                NotificationCenter.default.post(name: .focusNotesPanel, object: cell.id)
            } else {
                if let term = findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: container) {
                    window.makeFirstResponder(term)
                }
            }
        } else {
            // In git or notes panel → try next, then terminal
            if uiState.scratchPadVisible {
                NotificationCenter.default.post(name: .focusNotesPanel, object: cell.id)
            } else {
                if let term = findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: container) {
                    window.makeFirstResponder(term)
                }
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
