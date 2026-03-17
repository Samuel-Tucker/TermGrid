import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    var sessionManager: TerminalSessionManager
    @Bindable var vault: APIKeyVault
    var docsManager: DocsManager
    @State private var showAPILocker = false
    @State private var isLockerHovered = false
    @State private var cellUIStates: [UUID: CellUIState] = [:]

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
                                        sessionManager.createSession(for: cell.id, workingDirectory: cell.workingDirectory)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(padding)
        }
    }

    var body: some View {
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
            for id in cellIDs where cellUIStates[id] == nil {
                cellUIStates[id] = CellUIState()
            }
        }
        .onChange(of: vault.decryptedKeys) { _, newKeys in
            sessionManager.vaultKeys = newKeys
        }
        .onAppear {
            sessionManager.vaultKeys = vault.decryptedKeys
        }
    }
}
