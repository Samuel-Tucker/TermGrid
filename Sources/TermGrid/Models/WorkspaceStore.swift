import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceStore {
    var workspace: Workspace
    private let persistence: PersistenceManager
    private var saveTask: Task<Void, Never>?

    init(persistence: PersistenceManager = PersistenceManager()) {
        self.persistence = persistence
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

    // MARK: - Persistence

    func flush() {
        saveTask?.cancel()
        saveTask = nil
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
