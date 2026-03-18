import SwiftUI
import AppKit
import SwiftTerm

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    var sessionManager: TerminalSessionManager
    @Bindable var vault: APIKeyVault
    var docsManager: DocsManager
    var scrollbackManager: ScrollbackManager
    @State private var showAPILocker = false
    @State private var isLockerHovered = false
    @State private var cellUIStates: [UUID: CellUIState] = [:]
    @State private var focusedCellID: UUID? = nil
    @State private var focusMonitor: Any? = nil
    @State private var showCommandPalette = false
    @State private var commandRegistry = CommandRegistry()
    @State private var showFloatingPane = false

    private var rows: Int { store.workspace.gridLayout.rows }
    private var columns: Int { store.workspace.gridLayout.columns }

    private func uiState(for id: UUID) -> CellUIState {
        cellUIStates[id] ?? CellUIState()
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
                                    uiState: uiState(for: cell.id)
                                )
                                .frame(width: max(cellWidth, 100), height: max(cellHeight, 100))
                                .onAppear {
                                    if sessionManager.session(for: cell.id) == nil {
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
                                            uiState(for: cell.id).showExplorer = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(padding)
        }
        .overlay(alignment: .bottomTrailing) {
            if showFloatingPane, let session = sessionManager.floatingSession {
                FloatingPaneView(session: session, onDismiss: {
                    sessionManager.killFloatingSession()
                    showFloatingPane = false
                })
                .padding(16)
            }
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                gridContent
                if showAPILocker {
                    Divider()
                    APILockerPanel(vault: vault, docsManager: docsManager)
                }
            }
            .background(Theme.appBackground)
            .toolbar {
                ToolbarItem {
                    GridPickerView(selection: Binding(
                        get: { store.workspace.gridLayout },
                        set: { store.setGridPreset($0) }
                    ))
                }
                ToolbarItem {
                    Button {
                        showAPILocker.toggle()
                    } label: {
                        Image(systemName: vault.state == .noVault || vault.state == .locked
                              ? "lock.fill" : "lock.open.fill")
                            .foregroundColor(vault.state == .locked || vault.state == .noVault
                                             ? Theme.headerIcon : Theme.accent)
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) { isLockerHovered = hovering }
                    }
                    .overlay(alignment: .bottom) {
                        Text("API Locker")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.headerText)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.cellBackground)
                                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            )
                            .offset(y: isLockerHovered ? 28 : 20)
                            .opacity(isLockerHovered ? 1 : 0)
                    }
                }
            }
            .onChange(of: store.workspace.visibleCells.map(\.id), initial: true) { _, cellIDs in
                let idSet = Set(cellIDs)
                for id in cellIDs where cellUIStates[id] == nil {
                    cellUIStates[id] = CellUIState()
                }
                for key in cellUIStates.keys where !idSet.contains(key) {
                    cellUIStates.removeValue(forKey: key)
                }
            }
            .onChange(of: vault.decryptedKeys) { _, newKeys in
                sessionManager.vaultKeys = newKeys
            }
            .onAppear {
                sessionManager.vaultKeys = vault.decryptedKeys
                store.cellUIStates = cellUIStates
                // Clean up orphaned scrollback files
                let activeCellIDs = Set(store.workspace.cells.map(\.id))
                scrollbackManager.cleanupAll(keeping: activeCellIDs)
                focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
                    // Cmd+Shift+P toggles command palette
                    if event.type == .keyDown,
                       event.modifierFlags.contains([.command, .shift]),
                       event.charactersIgnoringModifiers == "p" {
                        showCommandPalette.toggle()
                        return nil // consume the event
                    }
                    if event.type == .keyDown,
                       event.modifierFlags.contains([.command, .shift]),
                       event.charactersIgnoringModifiers == "f" {
                        if showFloatingPane {
                            sessionManager.killFloatingSession()
                            showFloatingPane = false
                        } else {
                            sessionManager.createFloatingSession()
                            showFloatingPane = true
                        }
                        return nil
                    }
                    // Track focused cell on any event
                    DispatchQueue.main.async {
                        updateFocusedCell()
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
                showAPILocker.toggle()
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
                        sessionManager: sessionManager
                    ),
                    onDismiss: { showCommandPalette = false }
                )
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCommandPalette)
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
                        return
                    }
                    if let splitSession = sessionManager.splitSession(for: cell.id),
                       splitSession.terminalView === termView {
                        focusedCellID = cell.id
                        return
                    }
                }
            }
            view = v.superview
        }
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
}
