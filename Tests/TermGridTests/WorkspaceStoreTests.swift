import Foundation
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

    @Test func addPanelFrom1x1EscalatesTo2x1() {
        let ws = Workspace(gridLayout: .one_by_one)
        let store = WorkspaceStore(workspace: ws, scrollbackManager: ScrollbackManager())
        #expect(store.workspace.cells.count == 1)
        #expect(store.workspace.gridLayout == .one_by_one)
        let newID = store.addPanel()
        #expect(newID != nil)
        #expect(store.workspace.cells.count == 2)
        #expect(store.workspace.gridLayout == .two_by_one)
    }

    @Test func addPanelFillsEmptySlotWithoutEscalating() {
        let ws = Workspace(gridLayout: .two_by_two, cells: [Cell(), Cell(), Cell()])
        let store = WorkspaceStore(workspace: ws, scrollbackManager: ScrollbackManager())
        #expect(store.workspace.cells.count == 3)
        #expect(store.workspace.gridLayout == .two_by_two)
        let newID = store.addPanel()
        #expect(newID != nil)
        #expect(store.workspace.cells.count == 4)
        #expect(store.workspace.gridLayout == .two_by_two)
    }

    @Test func addPanelAtMaxReturnsNil() {
        let ws = Workspace(gridLayout: .three_by_three)
        let store = WorkspaceStore(workspace: ws, scrollbackManager: ScrollbackManager())
        #expect(store.workspace.cells.count == 9)
        let newID = store.addPanel()
        #expect(newID == nil)
        #expect(store.workspace.cells.count == 9)
    }

    @Test func canAddPanelReturnsCorrectValues() {
        let ws1 = Workspace(gridLayout: .one_by_one)
        let store1 = WorkspaceStore(workspace: ws1, scrollbackManager: ScrollbackManager())
        #expect(store1.canAddPanel == true)

        let ws9 = Workspace(gridLayout: .three_by_three)
        let store9 = WorkspaceStore(workspace: ws9, scrollbackManager: ScrollbackManager())
        #expect(store9.canAddPanel == false)
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

    // MARK: - swapCells Tests

    @Test func swapCellsSwapsCorrectly() {
        let ws = Workspace(gridLayout: .two_by_two)
        let store = WorkspaceStore(workspace: ws, scrollbackManager: ScrollbackManager())
        let idA = store.workspace.cells[0].id
        let idB = store.workspace.cells[2].id
        store.updateLabel("Alpha", for: idA)
        store.updateLabel("Bravo", for: idB)

        store.swapCells(idA, idB)

        // After swap, Alpha should be at index 2 and Bravo at index 0
        #expect(store.workspace.cells[0].label == "Bravo")
        #expect(store.workspace.cells[2].label == "Alpha")
        // IDs should follow the cells
        #expect(store.workspace.cells[0].id == idB)
        #expect(store.workspace.cells[2].id == idA)
    }

    @Test func swapCellsWithSameIDIsNoOp() {
        let ws = Workspace(gridLayout: .two_by_two)
        let store = WorkspaceStore(workspace: ws, scrollbackManager: ScrollbackManager())
        let idA = store.workspace.cells[0].id
        store.updateLabel("Stay", for: idA)
        let originalOrder = store.workspace.cells.map(\.id)

        store.swapCells(idA, idA)

        #expect(store.workspace.cells.map(\.id) == originalOrder)
        #expect(store.workspace.cells[0].label == "Stay")
    }

    @Test func swapCellsWithNonexistentIDIsNoOp() {
        let ws = Workspace(gridLayout: .two_by_two)
        let store = WorkspaceStore(workspace: ws, scrollbackManager: ScrollbackManager())
        let idA = store.workspace.cells[0].id
        let fakeID = UUID()
        let originalOrder = store.workspace.cells.map(\.id)

        store.swapCells(idA, fakeID)

        #expect(store.workspace.cells.map(\.id) == originalOrder)
    }

    @Test func swapCellsPreservesSessionKeyedData() {
        let ws = Workspace(gridLayout: .two_by_two)
        let store = WorkspaceStore(workspace: ws, scrollbackManager: ScrollbackManager())
        let idA = store.workspace.cells[0].id
        let idB = store.workspace.cells[1].id
        store.updateLabel("First", for: idA)
        store.updateNotes("Notes A", for: idA)
        store.updateLabel("Second", for: idB)
        store.updateNotes("Notes B", for: idB)

        store.swapCells(idA, idB)

        // Cell IDs are preserved — the cells moved, not just labels
        let cellA = store.workspace.cells.first(where: { $0.id == idA })!
        let cellB = store.workspace.cells.first(where: { $0.id == idB })!
        #expect(cellA.label == "First")
        #expect(cellA.notes == "Notes A")
        #expect(cellB.label == "Second")
        #expect(cellB.notes == "Notes B")
        // But their positions swapped
        #expect(store.workspace.cells[0].id == idB)
        #expect(store.workspace.cells[1].id == idA)
    }

    // O4: Close panels down to 1, then add — verify correct escalation
    @Test func closeThenAddPanelEscalatesCorrectly() {
        let ws = Workspace(gridLayout: .two_by_two) // 4 cells
        let store = WorkspaceStore(workspace: ws, scrollbackManager: ScrollbackManager())
        #expect(store.workspace.cells.count == 4)

        // Remove 3 cells — compactGrid should shrink to 1x1
        let idsToRemove = store.workspace.cells[1...3].map(\.id)
        for id in idsToRemove {
            store.removeCell(id: id)
        }
        #expect(store.workspace.cells.count == 1)
        #expect(store.workspace.gridLayout == .one_by_one)

        // Add panel — should escalate to 2x1
        let newID = store.addPanel()
        #expect(newID != nil)
        #expect(store.workspace.cells.count == 2)
        #expect(store.workspace.gridLayout == .two_by_one)
    }
}
