@testable import TermGrid
import Testing

private typealias H = WorkspaceStoreTestHelpers

@Suite("WorkspaceStore Tests")
@MainActor
struct WorkspaceStoreTests {

    @Test func initCreatesDefaultWorkspace() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        #expect(store.workspace.gridLayout == .two_by_two)
        #expect(store.workspace.cells.count == 4)
    }

    @Test func initLoadsExistingWorkspace() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let pm = H.makePM(directory: dir)
        let saved = Workspace(gridLayout: .three_by_three)
        try H.saveWorkspace(saved, using: pm)

        let store = WorkspaceStore(persistence: pm)
        #expect(store.workspace.gridLayout == .three_by_three)
        #expect(store.workspace.cells.count == 9)
    }

    @Test func updateLabel() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        let cellID = store.workspace.cells[0].id
        store.updateLabel("API Server", for: cellID)
        #expect(store.workspace.cells[0].label == "API Server")
    }

    @Test func updateNotes() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        let cellID = store.workspace.cells[0].id
        store.updateNotes("# Hello", for: cellID)
        #expect(store.workspace.cells[0].notes == "# Hello")
    }

    @Test func setGridPresetGrows() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        #expect(store.workspace.cells.count == 4)
        store.setGridPreset(.three_by_three)
        #expect(store.workspace.gridLayout == .three_by_three)
        #expect(store.workspace.cells.count == 9)
    }

    @Test func setGridPresetShrinkPreservesCells() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        store.updateLabel("Keep Me", for: store.workspace.cells[0].id)
        store.setGridPreset(.one_by_one)
        #expect(store.workspace.gridLayout == .one_by_one)
        #expect(store.workspace.cells.count == 4)
        #expect(store.workspace.cells[0].label == "Keep Me")
    }

    @Test func flushSavesImmediately() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let pm = H.makePM(directory: dir)
        let store = WorkspaceStore(persistence: pm)
        store.updateLabel("Flushed", for: store.workspace.cells[0].id)
        store.flush()

        let loaded = try H.loadWorkspace(using: pm)
        #expect(loaded?.cells[0].label == "Flushed")
    }
}
