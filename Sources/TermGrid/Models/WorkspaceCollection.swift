import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceCollection {
    private(set) var workspaces: [Workspace]
    var activeIndex: Int
    private(set) var activeStore: WorkspaceStore

    private let persistence: PersistenceManager
    private let scrollbackManager: ScrollbackManager
    private var saveTask: Task<Void, Never>?

    static let maxWorkspaces = 10

    init(persistence: PersistenceManager = PersistenceManager(),
         scrollbackManager: ScrollbackManager? = nil) {
        let sbm = scrollbackManager ?? ScrollbackManager()
        self.persistence = persistence
        self.scrollbackManager = sbm

        // Try collection format first, then migrate from legacy, then default
        let resolved: (workspaces: [Workspace], index: Int)
        if let collection = try? persistence.loadCollection(), !collection.workspaces.isEmpty {
            let idx = min(collection.activeWorkspaceIndex, collection.workspaces.count - 1)
            resolved = (collection.workspaces, idx)
        } else if let legacy = try? persistence.load() {
            var migrated = legacy
            if migrated.name == "" { migrated.name = "Default" }
            resolved = ([migrated], 0)
        } else {
            resolved = ([Workspace()], 0)
        }

        self.workspaces = resolved.workspaces
        self.activeIndex = resolved.index
        self.activeStore = WorkspaceStore(workspace: resolved.workspaces[resolved.index], scrollbackManager: sbm)
        wireOnSave()
    }

    /// Test-only init with explicit workspaces.
    init(workspaces: [Workspace], activeIndex: Int = 0,
         persistence: PersistenceManager, scrollbackManager: ScrollbackManager? = nil) {
        let sbm = scrollbackManager ?? ScrollbackManager()
        self.persistence = persistence
        self.scrollbackManager = sbm
        let ws = workspaces.isEmpty ? [Workspace()] : workspaces
        let idx = min(activeIndex, max(ws.count - 1, 0))
        self.workspaces = ws
        self.activeIndex = idx
        self.activeStore = WorkspaceStore(workspace: ws[idx], scrollbackManager: sbm)
        wireOnSave()
    }

    // MARK: - CRUD

    @discardableResult
    func createWorkspace(name: String? = nil) -> Int? {
        guard workspaces.count < Self.maxWorkspaces else { return nil }
        let newName = name ?? "Workspace \(workspaces.count + 1)"
        let ws = Workspace(name: newName)
        workspaces.append(ws)
        let newIndex = workspaces.count - 1
        switchToWorkspace(at: newIndex)
        scheduleSave()
        return newIndex
    }

    func switchToWorkspace(at index: Int) {
        guard index >= 0, index < workspaces.count else { return }
        // Sync current store back into array
        syncActiveStoreToArray()
        activeIndex = index
        let ws = workspaces[activeIndex]
        activeStore = WorkspaceStore(workspace: ws, scrollbackManager: scrollbackManager)
        wireOnSave()
    }

    func closeWorkspace(at index: Int) {
        guard workspaces.count > 1, index >= 0, index < workspaces.count else { return }
        // Clean up scrollback for closed workspace's cells
        let closing = workspaces[index]
        for cell in closing.cells {
            scrollbackManager.cleanup(cellID: cell.id)
        }

        workspaces.remove(at: index)

        if index == activeIndex {
            // Switch to adjacent
            let newIndex = min(index, workspaces.count - 1)
            activeIndex = newIndex
            let ws = workspaces[newIndex]
            activeStore = WorkspaceStore(workspace: ws, scrollbackManager: scrollbackManager)
            wireOnSave()
        } else if index < activeIndex {
            activeIndex -= 1
        }
        scheduleSave()
    }

    func renameWorkspace(at index: Int, to name: String) {
        guard index >= 0, index < workspaces.count else { return }
        workspaces[index].name = name
        if index == activeIndex {
            activeStore.workspace.name = name
        }
        scheduleSave()
    }

    func duplicateWorkspace(at index: Int) -> Int? {
        guard index >= 0, index < workspaces.count,
              workspaces.count < Self.maxWorkspaces else { return nil }
        let source = index == activeIndex ? activeStore.workspace : workspaces[index]
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " Copy"
        // Give each cell a new ID
        copy.cells = source.cells.map { cell in
            Cell(label: cell.label, notes: cell.notes,
                 workingDirectory: cell.workingDirectory,
                 terminalLabel: cell.terminalLabel,
                 splitTerminalLabel: cell.splitTerminalLabel,
                 explorerDirectory: cell.explorerDirectory,
                 explorerViewMode: cell.explorerViewMode)
        }
        workspaces.insert(copy, at: index + 1)
        switchToWorkspace(at: index + 1)
        scheduleSave()
        return index + 1
    }

    // MARK: - Persistence

    func persistCollection() {
        syncActiveStoreToArray()
        let data = WorkspaceCollectionData(
            activeWorkspaceIndex: activeIndex,
            workspaces: workspaces
        )
        do {
            try persistence.saveCollection(data)
        } catch {
            print("[TermGrid] Collection save failed: \(error)")
        }
    }

    func flush(sessionManager: TerminalSessionManager? = nil) {
        saveTask?.cancel()
        saveTask = nil
        // Flush active workspace scrollback (syncs split/explorer state too)
        activeStore.saveScrollback()
        syncActiveStoreToArray()
        // Flush background workspace sessions that are still alive
        if let sessionManager {
            for workspaceIndex in workspaces.indices where workspaceIndex != activeIndex {
                for cellIndex in workspaces[workspaceIndex].cells.indices {
                    let cellID = workspaces[workspaceIndex].cells[cellIndex].id

                    // Sync split direction
                    if let dir = sessionManager.splitDirection(for: cellID) {
                        workspaces[workspaceIndex].cells[cellIndex].splitDirection =
                            dir == .horizontal ? "horizontal" : "vertical"
                    } else {
                        workspaces[workspaceIndex].cells[cellIndex].splitDirection = nil
                    }

                    // Save primary scrollback
                    if let session = sessionManager.session(for: cellID) {
                        let data = session.getRawScrollback()
                        if !data.isEmpty {
                            try? scrollbackManager.saveRaw(cellID: cellID, sessionType: .primary, data: data)
                        }
                    }

                    // Save split scrollback
                    if let splitSession = sessionManager.splitSession(for: cellID) {
                        let data = splitSession.getRawScrollback()
                        if !data.isEmpty {
                            try? scrollbackManager.saveRaw(cellID: cellID, sessionType: .split, data: data)
                        }
                    }
                }
            }
        }
        persistCollection()
    }

    // MARK: - Private

    private func syncActiveStoreToArray() {
        guard activeIndex >= 0, activeIndex < workspaces.count else { return }
        workspaces[activeIndex] = activeStore.workspace
    }

    private func wireOnSave() {
        activeStore.onSave = { [weak self] in
            self?.scheduleSave()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.persistCollection()
        }
    }
}
