import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceStore {
    var workspace: Workspace
    private let persistence: PersistenceManager
    let scrollbackManager: ScrollbackManager
    private var saveTask: Task<Void, Never>?
    var sessionManager: TerminalSessionManager?
    var cellUIStates: [UUID: CellUIState]?

    init(persistence: PersistenceManager = PersistenceManager(),
         scrollbackManager: ScrollbackManager? = nil) {
        self.persistence = persistence
        self.scrollbackManager = scrollbackManager ?? ScrollbackManager()
        if let loaded = try? persistence.load() {
            self.workspace = loaded
        } else {
            self.workspace = .defaultWorkspace
        }
    }

    // MARK: - Mutation Methods

    func updateLabel(_ label: String, for cellID: UUID) {
        guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
        workspace.cells[index].label = label
        scheduleSave()
    }

    func updateNotes(_ notes: String, for cellID: UUID) {
        guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
        workspace.cells[index].notes = notes
        scheduleSave()
    }

    func updateWorkingDirectory(_ path: String, for cellID: UUID) {
        guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
        workspace.cells[index].workingDirectory = path
        scheduleSave()
    }

    func updateTerminalLabel(_ label: String, for cellID: UUID) {
        guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
        workspace.cells[index].terminalLabel = label
        scheduleSave()
    }

    func updateSplitTerminalLabel(_ label: String, for cellID: UUID) {
        guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
        workspace.cells[index].splitTerminalLabel = label
        scheduleSave()
    }

    func updateExplorerDirectory(_ path: String, for cellID: UUID) {
        guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
        workspace.cells[index].explorerDirectory = path
        scheduleSave()
    }

    func updateExplorerViewMode(_ mode: ExplorerViewMode, for cellID: UUID) {
        guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
        workspace.cells[index].explorerViewMode = mode
        scheduleSave()
    }

    func setGridPreset(_ preset: GridPreset) {
        workspace.gridLayout = preset
        let needed = preset.cellCount
        if workspace.cells.count < needed {
            let toAdd = needed - workspace.cells.count
            workspace.cells.append(contentsOf: (0..<toAdd).map { _ in Cell() })
        }
        // Don't remove excess cells — they are retained but hidden
        scheduleSave()
    }

    func removeCell(id: UUID) {
        workspace.cells.removeAll { $0.id == id }
        scrollbackManager.cleanup(cellID: id)
        compactGrid()
        scheduleSave()
    }

    private func compactGrid() {
        let count = workspace.cells.count
        let preset: GridPreset
        switch count {
        case 7...: preset = .three_by_three
        case 5...6: preset = .three_by_two
        case 4:     preset = .two_by_two
        case 3:     preset = .two_by_two
        case 2:     preset = .two_by_one
        default:    preset = .one_by_one
        }
        workspace.gridLayout = preset
    }

    // MARK: - Compose History

    func addToComposeHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Deduplicate: skip if the most recent entry has the same content
        if workspace.composeHistory.last?.content == trimmed { return }
        let entry = ComposeHistoryEntry(id: UUID(), content: trimmed, timestamp: Date())
        workspace.composeHistory.append(entry)
        // Ring buffer: cap at 100 entries
        if workspace.composeHistory.count > 100 {
            workspace.composeHistory.removeFirst(workspace.composeHistory.count - 100)
        }
        scheduleSave()
    }

    // MARK: - Persistence

    func saveScrollback() {
        guard let sessionManager else { return }

        for cell in workspace.visibleCells {
            if let idx = workspace.cells.firstIndex(where: { $0.id == cell.id }) {
                // Sync split direction from session manager
                if let dir = sessionManager.splitDirection(for: cell.id) {
                    workspace.cells[idx].splitDirection = dir == .horizontal ? "horizontal" : "vertical"
                } else {
                    workspace.cells[idx].splitDirection = nil
                }

                // Sync showExplorer from CellUIState
                if let uiState = cellUIStates?[cell.id] {
                    workspace.cells[idx].showExplorer = uiState.showExplorer
                }
            }

            // Save primary scrollback (raw PTY bytes)
            if let session = sessionManager.session(for: cell.id) {
                let data = session.getRawScrollback()
                if !data.isEmpty {
                    try? scrollbackManager.saveRaw(cellID: cell.id, sessionType: .primary, data: data)
                }
            }

            // Save split scrollback (raw PTY bytes)
            if let splitSession = sessionManager.splitSession(for: cell.id) {
                let data = splitSession.getRawScrollback()
                if !data.isEmpty {
                    try? scrollbackManager.saveRaw(cellID: cell.id, sessionType: .split, data: data)
                }
            }
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        saveScrollback()
        do {
            try persistence.save(workspace)
        } catch {
            print("[TermGrid] Save failed: \(error)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            do {
                try self.persistence.save(self.workspace)
            } catch {
                print("[TermGrid] Save failed: \(error)")
            }
        }
    }
}
