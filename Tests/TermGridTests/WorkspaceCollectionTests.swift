@testable import TermGrid
import Foundation
import Testing

@Suite("WorkspaceCollection Tests")
@MainActor
struct WorkspaceCollectionTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func removeTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Init

    @Test func initCreatesDefaultWorkspace() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let collection = WorkspaceCollection(persistence: PersistenceManager(directory: dir))
        #expect(collection.workspaces.count == 1)
        #expect(collection.workspaces[0].name == "Default")
        #expect(collection.activeIndex == 0)
    }

    @Test func initMigratesLegacyWorkspace() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let pm = PersistenceManager(directory: dir)
        // Save a legacy single workspace
        let legacy = Workspace(gridLayout: .three_by_two)
        try pm.save(legacy)

        let collection = WorkspaceCollection(persistence: pm)
        #expect(collection.workspaces.count == 1)
        #expect(collection.workspaces[0].name == "Default")
        #expect(collection.activeStore.workspace.gridLayout == .three_by_two)
    }

    @Test func initLoadsCollectionFormat() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let pm = PersistenceManager(directory: dir)
        let ws1 = Workspace(name: "Project A", gridLayout: .two_by_two)
        let ws2 = Workspace(name: "Project B", gridLayout: .three_by_two)
        let data = WorkspaceCollectionData(activeWorkspaceIndex: 1, workspaces: [ws1, ws2])
        try pm.saveCollection(data)

        let collection = WorkspaceCollection(persistence: pm)
        #expect(collection.workspaces.count == 2)
        #expect(collection.activeIndex == 1)
        #expect(collection.activeStore.workspace.name == "Project B")
        #expect(collection.activeStore.workspace.gridLayout == .three_by_two)
    }

    // MARK: - Create

    @Test func createWorkspace() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let collection = WorkspaceCollection(persistence: PersistenceManager(directory: dir))
        let index = collection.createWorkspace(name: "New WS")
        #expect(index == 1)
        #expect(collection.workspaces.count == 2)
        #expect(collection.workspaces[1].name == "New WS")
        #expect(collection.activeIndex == 1)
    }

    @Test func createWorkspaceAutoName() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let collection = WorkspaceCollection(persistence: PersistenceManager(directory: dir))
        collection.createWorkspace()
        #expect(collection.workspaces[1].name == "Workspace 2")
    }

    @Test func createWorkspaceCapsAt10() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let workspaces = (0..<10).map { Workspace(name: "WS \($0)") }
        let collection = WorkspaceCollection(
            workspaces: workspaces,
            persistence: PersistenceManager(directory: dir)
        )
        let result = collection.createWorkspace(name: "Overflow")
        #expect(result == nil)
        #expect(collection.workspaces.count == 10)
    }

    // MARK: - Switch

    @Test func switchWorkspace() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let ws1 = Workspace(name: "First", gridLayout: .two_by_two)
        let ws2 = Workspace(name: "Second", gridLayout: .three_by_two)
        let collection = WorkspaceCollection(
            workspaces: [ws1, ws2],
            persistence: PersistenceManager(directory: dir)
        )
        #expect(collection.activeIndex == 0)
        collection.switchToWorkspace(at: 1)
        #expect(collection.activeIndex == 1)
        #expect(collection.activeStore.workspace.name == "Second")
    }

    @Test func switchWorkspaceSyncsBack() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let ws1 = Workspace(name: "First")
        let ws2 = Workspace(name: "Second")
        let collection = WorkspaceCollection(
            workspaces: [ws1, ws2],
            persistence: PersistenceManager(directory: dir)
        )
        // Mutate the active store
        collection.activeStore.updateLabel("Modified", for: collection.activeStore.workspace.cells[0].id)
        // Switch away
        collection.switchToWorkspace(at: 1)
        // Check that changes were synced back
        #expect(collection.workspaces[0].cells[0].label == "Modified")
    }

    // MARK: - Close

    @Test func closeWorkspace() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let ws1 = Workspace(name: "First")
        let ws2 = Workspace(name: "Second")
        let collection = WorkspaceCollection(
            workspaces: [ws1, ws2],
            persistence: PersistenceManager(directory: dir)
        )
        collection.closeWorkspace(at: 0)
        #expect(collection.workspaces.count == 1)
        #expect(collection.workspaces[0].name == "Second")
        #expect(collection.activeIndex == 0)
    }

    @Test func closeLastWorkspaceRejected() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let collection = WorkspaceCollection(persistence: PersistenceManager(directory: dir))
        collection.closeWorkspace(at: 0)
        #expect(collection.workspaces.count == 1)
    }

    @Test func closeNonActiveWorkspace() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let ws1 = Workspace(name: "First")
        let ws2 = Workspace(name: "Second")
        let ws3 = Workspace(name: "Third")
        let collection = WorkspaceCollection(
            workspaces: [ws1, ws2, ws3],
            activeIndex: 2,
            persistence: PersistenceManager(directory: dir)
        )
        // Close workspace at index 0 (not active, which is 2)
        collection.closeWorkspace(at: 0)
        #expect(collection.workspaces.count == 2)
        #expect(collection.activeIndex == 1) // shifted down
        #expect(collection.workspaces[1].name == "Third")
    }

    // MARK: - Rename

    @Test func renameWorkspace() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let collection = WorkspaceCollection(persistence: PersistenceManager(directory: dir))
        collection.renameWorkspace(at: 0, to: "My Project")
        #expect(collection.workspaces[0].name == "My Project")
        #expect(collection.activeStore.workspace.name == "My Project")
    }

    // MARK: - Duplicate

    @Test func duplicateWorkspace() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let collection = WorkspaceCollection(persistence: PersistenceManager(directory: dir))
        collection.activeStore.updateLabel("Cell Label", for: collection.activeStore.workspace.cells[0].id)
        let newIndex = collection.duplicateWorkspace(at: 0)
        #expect(newIndex == 1)
        #expect(collection.workspaces.count == 2)
        #expect(collection.workspaces[1].name == "Default Copy")
        // Duplicated cells should have different IDs
        #expect(collection.workspaces[0].cells[0].id != collection.workspaces[1].cells[0].id)
        // But same label content
        #expect(collection.workspaces[1].cells[0].label == "Cell Label")
    }

    // MARK: - Persistence

    @Test func persistCollectionRoundTrip() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let pm = PersistenceManager(directory: dir)
        let collection = WorkspaceCollection(persistence: pm)
        collection.createWorkspace(name: "Second")
        collection.flush()

        // Load fresh
        let loaded = WorkspaceCollection(persistence: pm)
        #expect(loaded.workspaces.count == 2)
        #expect(loaded.workspaces[0].name == "Default")
        #expect(loaded.workspaces[1].name == "Second")
        #expect(loaded.activeIndex == 1)
    }

    @Test func flushSyncsBeforePersist() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let pm = PersistenceManager(directory: dir)
        let collection = WorkspaceCollection(persistence: pm)
        collection.activeStore.updateLabel("Flushed", for: collection.activeStore.workspace.cells[0].id)
        collection.flush()

        let loaded = WorkspaceCollection(persistence: pm)
        #expect(loaded.activeStore.workspace.cells[0].label == "Flushed")
    }
}
