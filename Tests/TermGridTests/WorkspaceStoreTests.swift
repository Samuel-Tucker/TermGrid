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

    @Test func updateWorkingDirectory() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        let cellID = store.workspace.cells[0].id
        store.updateWorkingDirectory("/tmp/myproject", for: cellID)
        #expect(store.workspace.cells[0].workingDirectory == "/tmp/myproject")
    }

    @Test func updateExplorerDirectory() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        let cellID = store.workspace.cells[0].id
        store.updateExplorerDirectory("/tmp/project", for: cellID)
        #expect(store.workspace.cells[0].explorerDirectory == "/tmp/project")
    }

    @Test func updateExplorerViewMode() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        let cellID = store.workspace.cells[0].id
        store.updateExplorerViewMode(.list, for: cellID)
        #expect(store.workspace.cells[0].explorerViewMode == .list)
    }

    @Test func removeCellRemovesFromArray() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        let cellID = store.workspace.cells[0].id
        let originalCount = store.workspace.cells.count
        store.removeCell(id: cellID)
        #expect(store.workspace.cells.count == originalCount - 1)
        #expect(!store.workspace.cells.contains(where: { $0.id == cellID }))
    }

    @Test func removeCellStaysAt2x2With3Cells() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        store.setGridPreset(.two_by_two)
        let cellToRemove = store.workspace.cells[3].id
        store.removeCell(id: cellToRemove)
        #expect(store.workspace.cells.count == 3)
        #expect(store.workspace.gridLayout == .two_by_two)
    }

    @Test func removeCellCompactsGrid2x2To2x1() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        store.setGridPreset(.two_by_two)
        store.removeCell(id: store.workspace.cells[3].id)
        store.removeCell(id: store.workspace.cells[2].id)
        #expect(store.workspace.cells.count == 2)
        #expect(store.workspace.gridLayout == .two_by_one)
    }

    @Test func removeCellCompactsGrid2x2To1x1() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        store.setGridPreset(.two_by_two)
        store.removeCell(id: store.workspace.cells[3].id)
        store.removeCell(id: store.workspace.cells[2].id)
        store.removeCell(id: store.workspace.cells[1].id)
        #expect(store.workspace.cells.count == 1)
        #expect(store.workspace.gridLayout == .one_by_one)
    }

    @Test func removeCellFrom3x3To3x2() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let store = H.makeStore(directory: dir)
        store.setGridPreset(.three_by_three)
        for _ in 0..<4 {
            store.removeCell(id: store.workspace.cells.last!.id)
        }
        #expect(store.workspace.cells.count == 5)
        #expect(store.workspace.gridLayout == .three_by_two)
    }

    @Test func removeLastCellLeavesEmpty1x1() throws {
        let dir = try H.makeTempDir()
        defer { H.removeTempDir(dir) }
        let pm = H.makePM(directory: dir)
        let saved = Workspace(gridLayout: .one_by_one)
        try H.saveWorkspace(saved, using: pm)
        let store = WorkspaceStore(persistence: pm)
        #expect(store.workspace.cells.count == 1)
        store.removeCell(id: store.workspace.cells[0].id)
        #expect(store.workspace.cells.count == 0)
        #expect(store.workspace.gridLayout == .one_by_one)
    }
}
