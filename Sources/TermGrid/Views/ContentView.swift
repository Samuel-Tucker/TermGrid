import SwiftUI
import AppKit
import SwiftTerm

struct ContentView: View {
    @Bindable var collection: WorkspaceCollection
    var sessionManager: TerminalSessionManager
    @Bindable var vault: APIKeyVault
    var docsManager: DocsManager
    var completionEngine: CompletionEngine

    private var store: WorkspaceStore { collection.activeStore }
    private var scrollbackManager: ScrollbackManager { store.scrollbackManager }
    var skillsManager: SkillsManager

    enum SidePanel { case none, skills, apiLocker }
    @State private var sidePanel: SidePanel = .none
    @State private var isLockerHovered = false
    @State private var isSkillsHovered = false
    @State private var cellUIStates: [UUID: CellUIState] = [:]
    @State private var focusedCellID: UUID? = nil
    @State private var focusMonitor: Any? = nil
    @State private var showCommandPalette = false
    @State private var commandRegistry = CommandRegistry()
    @State private var showFloatingPane = false
    @State private var isFloatHovered = false
    @State private var hoveredCellID: UUID? = nil
    @State private var scrollMonitor: Any? = nil
    @State private var lastScrollCycleTime: Date = .distantPast
    @State private var isAddPanelHovered = false
    @State private var showPopoutReader = false
    @State private var popoutContent: ExtractedContent? = nil
    @State private var popoutCellLabel: String = ""
    @State private var popoutAgentType: AgentType? = nil
    @State private var panelDrag = PanelDragState()
    @State private var cellFrames: [UUID: CGRect] = [:]

    private var rows: Int { store.workspace.gridLayout.rows }
    private var columns: Int { store.workspace.gridLayout.columns }

    // Read-only lookup — NEVER mutate @State during body evaluation.
    // States are seeded in the onChange handler below.
    private static let fallbackUIState = CellUIState()

    private func uiState(for id: UUID) -> CellUIState {
        cellUIStates[id] ?? Self.fallbackUIState
    }

    private var gridContent: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let padding: CGFloat = 16
            let totalHSpacing = spacing * CGFloat(columns - 1) + padding * 2
            let totalVSpacing = spacing * CGFloat(rows - 1) + padding * 2
            let cellWidth = (geo.size.width - totalHSpacing) / CGFloat(columns)
            let cellHeight = (geo.size.height - totalVSpacing) / CGFloat(rows)
            let cells = store.workspace.visibleCells

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { (row: Int) in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { (col: Int) in
                            let index = row * columns + col
                            if index < cells.count {
                                let cell = cells[index]
                                cellContent(cell: cell, cellWidth: cellWidth, cellHeight: cellHeight)
                            }
                        }
                    }
                }
            }
            .padding(padding)
            .coordinateSpace(name: "grid")
            .onPreferenceChange(CellFramePreferenceKey.self) { cellFrames = $0 }
            .onChange(of: store.workspace.gridLayout) { _, _ in
                if panelDrag.isDragging { panelDrag.reset() }
            }

            // Drag preview overlay
            if panelDrag.isDragging, let dragID = panelDrag.draggingCellID,
               let cell = store.workspace.visibleCells.first(where: { $0.id == dragID }),
               let sourceFrame = cellFrames[dragID] {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.cellBackground.opacity(0.85))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(Theme.accent)
                            Text(cell.label.isEmpty ? "Terminal" : cell.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.headerText)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.accent, lineWidth: 1.5)
                    )
                    .frame(width: sourceFrame.width * 0.4, height: sourceFrame.height * 0.4)
                    .position(
                        x: sourceFrame.midX + panelDrag.dragOffset.width,
                        y: sourceFrame.midY + panelDrag.dragOffset.height
                    )
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showFloatingPane, let session = sessionManager.floatingSession {
                FloatingPaneView(
                    session: session,
                    onDismiss: {
                        sessionManager.killFloatingSession()
                        showFloatingPane = false
                    },
                    onDropIntoGrid: {
                        dropFloatingPaneIntoGrid()
                    }
                )
                .padding(16)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.canAddPanel && !showFloatingPane {
                addPanelButton
                    .padding(16)
            }
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                WorkspaceTabBar(
                    collection: collection,
                    onSwitchWorkspace: { switchWorkspace(to: $0) },
                    onNewWorkspace: { createNewWorkspace() },
                    onCloseWorkspace: { closeWorkspace(at: $0) },
                    onRenameWorkspace: { collection.renameWorkspace(at: $0, to: $1) },
                    onDuplicateWorkspace: { duplicateWorkspace(at: $0) }
                )
                Divider().foregroundColor(Theme.divider)
                gridContent
            }
            switch sidePanel {
            case .skills:
                Divider()
                SkillsPanel(
                    skillsManager: skillsManager,
                    onSendToCompose: { content in injectIntoFocusedCell(content) }
                )
            case .apiLocker:
                Divider()
                APILockerPanel(vault: vault, docsManager: docsManager)
            case .none:
                EmptyView()
            }
        }
        .background(Theme.appBackground)
        .toolbar { toolbarContent }
        .onChange(of: Set(store.workspace.visibleCells.map(\.id)), initial: true) { oldIDs, newIDs in
            guard oldIDs != newIDs else { return } // Skip if only order changed (e.g. swap)
            for id in newIDs where cellUIStates[id] == nil {
                cellUIStates[id] = CellUIState()
            }
            for key in cellUIStates.keys where !newIDs.contains(key) {
                cellUIStates.removeValue(forKey: key)
            }
        }
        .onChange(of: vault.decryptedKeys) { _, newKeys in
            sessionManager.vaultKeys = newKeys
        }
        .onAppear {
            // Seed CellUIState for all visible cells BEFORE first render
            for cell in store.workspace.visibleCells where cellUIStates[cell.id] == nil {
                cellUIStates[cell.id] = CellUIState()
            }
            sessionManager.vaultKeys = vault.decryptedKeys
            store.cellUIStates = cellUIStates
            // Clean up orphaned scrollback files (check all workspaces)
            let activeCellIDs = Set(collection.workspaces.flatMap(\.cells).map(\.id))
            scrollbackManager.cleanupAll(keeping: activeCellIDs)
            installKeyboardMonitors()
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
            if let monitor = focusMonitor {
                NSEvent.removeMonitor(monitor)
                focusMonitor = nil
            }
        }
    }

    private var notificationReceivers: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in
                showCommandPalette.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFloatingPane)) { _ in
                if showFloatingPane {
                    sessionManager.killFloatingSession()
                    showFloatingPane = false
                } else {
                    sessionManager.createFloatingSession()
                    showFloatingPane = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteToggleAPILocker)) { _ in
                sidePanel = sidePanel == .apiLocker ? .none : .apiLocker
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteToggleSkills)) { _ in
                sidePanel = sidePanel == .skills ? .none : .skills
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteSwitchGrid)) { _ in
                let presets = GridPreset.allCases
                if let idx = presets.firstIndex(of: store.workspace.gridLayout),
                   idx + 1 < presets.count {
                    store.setGridPreset(presets[idx + 1])
                } else {
                    store.setGridPreset(presets[0])
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteNewWorkspace)) { _ in
                createNewWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteCloseWorkspace)) { _ in
                closeWorkspace(at: collection.activeIndex)
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteNextWorkspace)) { _ in
                let next = (collection.activeIndex + 1) % collection.workspaces.count
                switchWorkspace(to: next)
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPalettePrevWorkspace)) { _ in
                let prev = (collection.activeIndex - 1 + collection.workspaces.count) % collection.workspaces.count
                switchWorkspace(to: prev)
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteSwapDirection)) { notification in
                swapFocusedCell(direction: notification.object as? String ?? "right")
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteAddPanel)) { _ in
                if store.canAddPanel {
                    withAnimation(.easeInOut(duration: 0.2)) { _ = store.addPanel() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .commandPalettePopoutReader)) { _ in
                triggerPopoutForFocusedCell()
            }
    }

    var body: some View {
        ZStack {
            mainContent
            notificationReceivers

            // Command palette overlay
            if showCommandPalette {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showCommandPalette = false
                    }

                CommandPaletteView(
                    registry: commandRegistry,
                    context: CommandContext(
                        focusedCellID: focusedCellID,
                        cellUIState: focusedCellID.flatMap { cellUIStates[$0] },
                        store: store,
                        sessionManager: sessionManager,
                        collection: collection
                    ),
                    onDismiss: { showCommandPalette = false }
                )
            }

            // Popout reader overlay
            if showPopoutReader, let content = popoutContent {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showPopoutReader = false
                        popoutContent = nil
                    }

                PopoutReaderView(
                    content: content,
                    cellLabel: popoutCellLabel,
                    agentType: popoutAgentType,
                    onDismiss: {
                        showPopoutReader = false
                        popoutContent = nil
                    },
                    onRefresh: {
                        triggerPopoutForFocusedCell()
                    }
                )
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCommandPalette)
        .animation(.easeOut(duration: 0.15), value: showPopoutReader)
    }

    private func installKeyboardMonitors() {
        focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
            if event.type == .keyDown {
                if let result = handleKeyDown(event) { return result }
            }
            // Track focused cell on any event
            DispatchQueue.main.async { updateFocusedCell() }
            return event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            guard abs(event.deltaY) > 0.5 else { return event }
            if event.momentumPhase != [] { return event }
            let now = Date()
            guard now.timeIntervalSince(lastScrollCycleTime) > 0.15 else { return nil }
            lastScrollCycleTime = now
            cycleCell(forward: event.deltaY < 0)
            return nil
        }
    }

    /// Returns nil to consume the event, or the event to pass it through.
    /// Returns .some(nil) when the event should be consumed.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent?? {
        // Suppress keyboard during panel drag
        if panelDrag.isDragging {
            if event.keyCode == 53 { // Escape
                withAnimation(.easeInOut(duration: 0.15)) { panelDrag.reset() }
            }
            return .some(nil)
        }

        // Escape dismisses popout reader
        if event.keyCode == 53 && showPopoutReader {
            showPopoutReader = false
            popoutContent = nil
            return .some(nil)
        }

        let mods = event.modifierFlags
        let chars = event.charactersIgnoringModifiers

        // Cmd+Shift shortcuts
        if mods.contains([.command, .shift]) {
            switch chars {
            case "p": showCommandPalette.toggle(); return .some(nil)
            case "f":
                if showFloatingPane { sessionManager.killFloatingSession(); showFloatingPane = false }
                else { sessionManager.createFloatingSession(); showFloatingPane = true }
                return .some(nil)
            case "w": closeWorkspace(at: collection.activeIndex); return .some(nil)
            case "[":
                let prev = (collection.activeIndex - 1 + collection.workspaces.count) % collection.workspaces.count
                switchWorkspace(to: prev)
                return .some(nil)
            case "]":
                let next = (collection.activeIndex + 1) % collection.workspaces.count
                switchWorkspace(to: next)
                return .some(nil)
            case "n":
                if store.canAddPanel {
                    withAnimation(.easeInOut(duration: 0.2)) { _ = store.addPanel() }
                }
                return .some(nil)
            case "e":
                triggerPopoutForFocusedCell()
                return .some(nil)
            default: break
            }
        }

        // Cmd (no shift) shortcuts
        if mods.contains(.command), !mods.contains(.shift), !mods.contains(.option) {
            if chars == "t" { createNewWorkspace(); return .some(nil) }
            if let c = chars, let digit = Int(c), digit >= 1, digit <= 9 {
                let index = digit - 1
                if index < collection.workspaces.count { switchWorkspace(to: index) }
                return .some(nil)
            }
        }

        // Phantom compose activation — pane-aware for split terminals
        if let focused = identifyFocusedPane(),
           let uiState = cellUIStates[focused.cellID],
           uiState.phantomComposeEnabled {
            let pane = focused.isSplit ? uiState.splitPane : uiState.primaryPane
            if !pane.phantomComposeActive {
                let flags = mods.intersection(.deviceIndependentFlagsMask)
                if !flags.contains(.command) && !flags.contains(.control) {
                    let nonPrintable: Set<UInt16> = [
                        48, 51, 53, 117, 123, 124, 125, 126,
                        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                        115, 119, 116, 121, 36, 76,
                    ]
                    if !nonPrintable.contains(event.keyCode),
                       let eventChars = event.characters, !eventChars.isEmpty {
                        pane.phantomPendingCharacter = eventChars
                        pane.phantomComposeActive = true
                        return .some(nil)
                    }
                }
            }
        }

        return nil // not handled — pass through
    }

    /// Synchronously identify which cell's terminal is the current first responder.
    private func identifyFocusedCell() -> UUID? {
        identifyFocusedPane()?.cellID
    }

    /// Returns the focused cell ID and whether the split pane is focused.
    private func identifyFocusedPane() -> (cellID: UUID, isSplit: Bool)? {
        guard let window = NSApp.keyWindow,
              let responder = window.firstResponder as? NSView else { return nil }
        for cell in store.workspace.visibleCells {
            if let session = sessionManager.session(for: cell.id),
               session.terminalView === responder {
                return (cell.id, false)
            }
            if let splitSession = sessionManager.splitSession(for: cell.id),
               splitSession.terminalView === responder {
                return (cell.id, true)
            }
        }
        return nil
    }

    private func updateFocusedCell() {
        guard let window = NSApp.keyWindow,
              let responder = window.firstResponder as? NSView else { return }

        var view: NSView? = responder
        while let v = view {
            if let termView = findTerminalView(in: v) {
                for cell in store.workspace.visibleCells {
                    if let session = sessionManager.session(for: cell.id),
                       session.terminalView === termView {
                        focusedCellID = cell.id
                        sessionManager.notificationState(for: cell.id).clear()
                        return
                    }
                    if let splitSession = sessionManager.splitSession(for: cell.id),
                       splitSession.terminalView === termView {
                        focusedCellID = cell.id
                        sessionManager.notificationState(for: cell.id).clear()
                        return
                    }
                }
            }
            view = v.superview
        }
    }

    private func cycleCell(forward: Bool) {
        let cells = store.workspace.visibleCells
        guard !cells.isEmpty else { return }

        let currentIndex = cells.firstIndex(where: { $0.id == focusedCellID }) ?? -1
        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % cells.count
        } else {
            nextIndex = (currentIndex - 1 + cells.count) % cells.count
        }

        let targetCell = cells[nextIndex]
        focusedCellID = targetCell.id
        sessionManager.notificationState(for: targetCell.id).clear()

        if let session = sessionManager.session(for: targetCell.id),
           let window = NSApp.keyWindow {
            window.makeFirstResponder(session.terminalView)
        }
    }

    private func dropFloatingPaneIntoGrid() {
        guard sessionManager.floatingSession != nil else { return }
        guard let newCellID = store.addPanel() else { return }
        sessionManager.adoptFloatingSession(for: newCellID)
        showFloatingPane = false
    }

    private func findTerminalView(in view: NSView) -> NSView? {
        if view is SwiftTerm.LocalProcessTerminalView {
            return view
        }
        for subview in view.subviews {
            if let found = findTerminalView(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Toolbar (extracted to reduce type-checker load)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            GridPickerView(selection: Binding(
                get: { store.workspace.gridLayout },
                set: { store.setGridPreset($0) }
            ))
        }
        ToolbarItem {
            Button {
                if showFloatingPane {
                    sessionManager.killFloatingSession()
                    showFloatingPane = false
                } else {
                    sessionManager.createFloatingSession()
                    showFloatingPane = true
                }
            } label: {
                Image(systemName: showFloatingPane ? "pip.fill" : "pip")
                    .foregroundColor(showFloatingPane ? Theme.accent : Theme.headerIcon)
            }
            .tooltip("Quick Terminal (⌘⇧F)")
        }
        ToolbarItem {
            Button {
                sidePanel = sidePanel == .skills ? .none : .skills
            } label: {
                Image(systemName: "book")
                    .foregroundColor(sidePanel == .skills ? Theme.accent : Theme.headerIcon)
            }
            .tooltip("Skills")
        }
        ToolbarItem {
            Button {
                sidePanel = sidePanel == .apiLocker ? .none : .apiLocker
            } label: {
                Image(systemName: vault.state == .noVault || vault.state == .locked
                      ? "lock.fill" : "lock.open.fill")
                    .foregroundColor(vault.state == .locked || vault.state == .noVault
                                     ? Theme.headerIcon : Theme.accent)
            }
            .tooltip("API Locker")
        }
    }

    // MARK: - Popout Reader

    private func triggerPopoutForFocusedCell() {
        guard let cellID = focusedCellID,
              let session = sessionManager.session(for: cellID) else { return }
        let cell = store.workspace.visibleCells.first(where: { $0.id == cellID })
        let terminal = session.terminalView.getTerminal()
        let bufferData = terminal.getBufferAsData(kind: .normal)
        let rawText = String(data: bufferData, encoding: .utf8) ?? ""
        let extracted = TerminalContentExtractor.extractLastOutput(from: rawText)
        popoutContent = extracted
        popoutCellLabel = cell?.label ?? ""
        popoutAgentType = session.detectedAgent
        showPopoutReader = true
    }

    // MARK: - Skill Injection

    @discardableResult
    private func injectIntoFocusedCell(_ content: String) -> Bool {
        guard let cellID = focusedCellID,
              let uiState = cellUIStates[cellID],
              uiState.phantomComposeEnabled else { return false }
        uiState.phantomComposeText = content
        uiState.phantomComposeActive = true
        uiState.phantomPendingCharacter = nil
        return true
    }

    // MARK: - Add Panel Button (compact floating)

    private var addPanelButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { _ = store.addPanel() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isAddPanelHovered ? .white : Theme.accent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.ultraThinMaterial)
                )
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.cellBackground.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            isAddPanelHovered ? Theme.accent : Theme.accent.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                )
                .scaleEffect(isAddPanelHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isAddPanelHovered = hovering }
        }
        .tooltip("Add Panel (⌘⇧N)")
    }

    // MARK: - Cell Content (outside GeometryReader for reliable @Observable tracking)

    @ViewBuilder
    private func cellContent(cell: Cell, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let session = sessionManager.session(for: cell.id)
        let splitSession = sessionManager.splitSession(for: cell.id)
        let splitDir = sessionManager.splitDirection(for: cell.id)
        CellView(
            cell: cell,
            session: session,
            splitSession: splitSession,
            splitDirection: splitDir,
            onUpdateLabel: { store.updateLabel($0, for: cell.id) },
            onUpdateNotes: { store.updateNotes($0, for: cell.id) },
            onUpdateWorkingDirectory: { newPath in
                store.updateWorkingDirectory(newPath, for: cell.id)
                sessionManager.createSession(for: cell.id, workingDirectory: newPath)
                if let dir = sessionManager.splitDirection(for: cell.id) {
                    sessionManager.createSplitSession(for: cell.id, workingDirectory: newPath, direction: dir)
                }
            },
            onRestartSession: {
                sessionManager.createSession(for: cell.id, workingDirectory: cell.workingDirectory)
            },
            onToggleSplit: { direction in
                if sessionManager.splitDirection(for: cell.id) == direction {
                    sessionManager.killSplitSession(for: cell.id)
                } else if sessionManager.splitSession(for: cell.id) != nil {
                    sessionManager.changeSplitDirection(for: cell.id, to: direction)
                } else {
                    sessionManager.createSplitSession(for: cell.id, workingDirectory: cell.workingDirectory, direction: direction)
                }
            },
            onRestartSplitSession: {
                let dir = sessionManager.splitDirection(for: cell.id) ?? .horizontal
                sessionManager.createSplitSession(for: cell.id, workingDirectory: cell.workingDirectory, direction: dir)
            },
            onUpdateTerminalLabel: { store.updateTerminalLabel($0, for: cell.id) },
            onUpdateSplitTerminalLabel: { store.updateSplitTerminalLabel($0, for: cell.id) },
            onUpdateExplorerDirectory: { newPath in
                store.updateExplorerDirectory(newPath, for: cell.id)
            },
            onUpdateExplorerViewMode: { mode in
                store.updateExplorerViewMode(mode, for: cell.id)
            },
            onCloseCell: {
                sessionManager.killSession(for: cell.id)
                store.removeCell(id: cell.id)
            },
            composeHistory: store.workspace.composeHistory,
            onAddToComposeHistory: { store.addToComposeHistory($0) },
            uiState: uiState(for: cell.id),
            notificationState: sessionManager.notificationState(for: cell.id),
            completionEngine: completionEngine,
            showDragHandle: store.workspace.visibleCells.count > 1,
            onDragChanged: { translation in handleDragChanged(cellID: cell.id, translation: translation) },
            onDragEnded: { handleDragEnded() }
        )
        .id(cell.id)
        .frame(width: max(cellWidth, 100), height: max(cellHeight, 100))
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CellFramePreferenceKey.self,
                    value: [cell.id: geo.frame(in: .named("grid"))]
                )
            }
        )
        .opacity(panelDrag.draggingCellID == cell.id ? 0.4 : 1.0)
        .overlay {
            if panelDrag.dropTargetCellID == cell.id {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if hoveredCellID != nil && hoveredCellID != cell.id {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.appBackground.opacity(0.3))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                if hovering {
                    hoveredCellID = cell.id
                } else if hoveredCellID == cell.id {
                    hoveredCellID = nil
                }
            }
        }
        .task(id: cell.id) {
            ensureSession(for: cell)
        }
    }

    // MARK: - Session Creation

    private func ensureSession(for cell: Cell) {
        guard sessionManager.session(for: cell.id) == nil else { return }

        // Restore split if persisted
        if let dirStr = cell.splitDirection {
            let dir: SplitDirection = dirStr == "horizontal" ? .horizontal : .vertical
            let splitData = scrollbackManager.loadRaw(cellID: cell.id, sessionType: .split)
            let splitSession = sessionManager.createSplitSession(
                for: cell.id, workingDirectory: cell.workingDirectory,
                direction: dir, startImmediately: splitData == nil
            )
            if let data = splitData {
                splitSession.replayScrollback(data)
                splitSession.start()
            }
        }

        // Create primary session
        let primaryData = scrollbackManager.loadRaw(cellID: cell.id, sessionType: .primary)
        let session = sessionManager.createSession(
            for: cell.id, workingDirectory: cell.workingDirectory,
            startImmediately: primaryData == nil
        )
        if let data = primaryData {
            session.replayScrollback(data)
            session.start()
        }

        // Restore explorer state
        if cell.showExplorer {
            uiState(for: cell.id).bodyMode = .explorer
        }
    }

    // MARK: - Workspace Switching

    private func switchWorkspace(to index: Int) {
        guard index != collection.activeIndex else { return }
        // 1. Save scrollback for current workspace
        store.saveScrollback()
        // 2. Kill all sessions for current workspace cells
        for cell in store.workspace.visibleCells {
            sessionManager.killSession(for: cell.id)
            sessionManager.killSplitSession(for: cell.id)
        }
        // 3. Clear UI states
        cellUIStates.removeAll()
        focusedCellID = nil
        // 4. Switch
        collection.switchToWorkspace(at: index)
        // 5. Wire new store
        collection.activeStore.sessionManager = sessionManager
        collection.activeStore.cellUIStates = cellUIStates
    }

    private func createNewWorkspace() {
        store.saveScrollback()
        for cell in store.workspace.visibleCells {
            sessionManager.killSession(for: cell.id)
            sessionManager.killSplitSession(for: cell.id)
        }
        cellUIStates.removeAll()
        focusedCellID = nil
        collection.createWorkspace()
        collection.activeStore.sessionManager = sessionManager
        collection.activeStore.cellUIStates = cellUIStates
    }

    private func closeWorkspace(at index: Int) {
        guard collection.workspaces.count > 1 else { return }
        let wasActive = index == collection.activeIndex
        if wasActive {
            for cell in store.workspace.visibleCells {
                sessionManager.killSession(for: cell.id)
                sessionManager.killSplitSession(for: cell.id)
            }
            cellUIStates.removeAll()
            focusedCellID = nil
        }
        collection.closeWorkspace(at: index)
        if wasActive {
            collection.activeStore.sessionManager = sessionManager
            collection.activeStore.cellUIStates = cellUIStates
        }
    }

    private func duplicateWorkspace(at index: Int) {
        store.saveScrollback()
        for cell in store.workspace.visibleCells {
            sessionManager.killSession(for: cell.id)
            sessionManager.killSplitSession(for: cell.id)
        }
        cellUIStates.removeAll()
        focusedCellID = nil
        _ = collection.duplicateWorkspace(at: index)
        collection.activeStore.sessionManager = sessionManager
        collection.activeStore.cellUIStates = cellUIStates
    }

    // MARK: - Panel Drag

    private func handleDragChanged(cellID: UUID, translation: CGSize) {
        if panelDrag.draggingCellID == nil {
            panelDrag.draggingCellID = cellID
        }
        panelDrag.dragOffset = translation

        // Hit test for drop target
        guard let sourceFrame = cellFrames[cellID] else { return }
        let dragPoint = CGPoint(
            x: sourceFrame.midX + translation.width,
            y: sourceFrame.midY + translation.height
        )
        var found: UUID? = nil
        for (id, frame) in cellFrames where id != cellID {
            if frame.contains(dragPoint) {
                found = id
                break
            }
        }
        panelDrag.dropTargetCellID = found
    }

    private func handleDragEnded() {
        if let sourceID = panelDrag.draggingCellID,
           let targetID = panelDrag.dropTargetCellID,
           sourceID != targetID {
            withAnimation(.easeInOut(duration: 0.25)) {
                store.swapCells(sourceID, targetID)
            }
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            panelDrag.reset()
        }
    }

    // MARK: - Directional Swap (O3)

    private func swapFocusedCell(direction: String) {
        let cells = store.workspace.visibleCells
        guard cells.count > 1,
              let cellID = focusedCellID,
              let currentIdx = cells.firstIndex(where: { $0.id == cellID }) else { return }

        let cols = store.workspace.gridLayout.columns
        let targetIdx: Int
        switch direction {
        case "left":  targetIdx = currentIdx - 1
        case "right": targetIdx = currentIdx + 1
        case "up":    targetIdx = currentIdx - cols
        case "down":  targetIdx = currentIdx + cols
        default:      targetIdx = currentIdx + 1
        }

        guard targetIdx >= 0, targetIdx < cells.count, targetIdx != currentIdx else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            store.swapCells(cells[currentIdx].id, cells[targetIdx].id)
        }
    }
}

// MARK: - Cell Frame Preference Key

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
