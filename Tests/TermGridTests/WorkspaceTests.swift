@testable import TermGrid
import Foundation
import Testing

@Suite("ExplorerViewMode Tests")
struct ExplorerViewModeTests {
    @Test func rawValueRoundTrip() {
        #expect(ExplorerViewMode(rawValue: "grid") == .grid)
        #expect(ExplorerViewMode(rawValue: "list") == .list)
        #expect(ExplorerViewMode(rawValue: "unknown") == nil)
    }
}

@Suite("GridPreset Tests")
struct GridPresetTests {
    @Test func columnsAndRows() {
        #expect(GridPreset.one_by_one.columns == 1)
        #expect(GridPreset.one_by_one.rows == 1)
        #expect(GridPreset.two_by_two.columns == 2)
        #expect(GridPreset.two_by_two.rows == 2)
        #expect(GridPreset.three_by_two.columns == 3)
        #expect(GridPreset.three_by_two.rows == 2)
        #expect(GridPreset.two_by_three.columns == 2)
        #expect(GridPreset.two_by_three.rows == 3)
    }

    @Test func cellCount() {
        #expect(GridPreset.one_by_one.cellCount == 1)
        #expect(GridPreset.two_by_two.cellCount == 4)
        #expect(GridPreset.three_by_two.cellCount == 6)
        #expect(GridPreset.three_by_three.cellCount == 9)
    }

    @Test func rawValueRoundTrip() {
        for preset in [GridPreset.one_by_one, .two_by_one, .one_by_two,
                       .two_by_two, .three_by_two, .two_by_three, .three_by_three] {
            #expect(GridPreset(rawValue: preset.rawValue) == preset)
        }
    }
}

@Suite("Workspace Codable Tests")
struct WorkspaceCodableTests {
    @Test func roundTrip() throws {
        let workspace = Workspace(gridLayout: .three_by_two)
        let data = try TestHelpers.encodeWorkspace(workspace)
        let decoded = try TestHelpers.decodeWorkspace(from: data)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.gridLayout == GridPreset.three_by_two)
        #expect(decoded.cells.count == 6)
    }

    @Test func missingSchemaVersionDefaultsToOne() throws {
        let decoded = try TestHelpers.decodeWorkspace(fromJSON: """
        {"gridLayout":"2x2","cells":[]}
        """)
        #expect(decoded.schemaVersion == 1)
    }

    @Test func unknownGridLayoutDefaultsToTwoByTwo() throws {
        let decoded = try TestHelpers.decodeWorkspace(fromJSON: """
        {"schemaVersion":1,"gridLayout":"5x5","cells":[]}
        """)
        #expect(decoded.gridLayout == GridPreset.two_by_two)
    }

    @Test func visibleCellsReturnsPrefix() {
        let cells = (0..<9).map { _ in Cell() }
        let workspace = Workspace(gridLayout: .two_by_two, cells: cells)
        #expect(workspace.visibleCells.count == 4)
    }

    @Test func visibleCellsHandlesUnderfill() {
        let workspace = Workspace(gridLayout: .two_by_two, cells: [Cell()])
        #expect(workspace.visibleCells.count == 1)
    }
}

@Suite("Workspace Identity Tests")
struct WorkspaceIdentityTests {
    @Test func defaultIdAndName() {
        let ws = Workspace()
        #expect(!ws.id.uuidString.isEmpty)
        #expect(ws.name == "Default")
    }

    @Test func customNamePreserved() {
        let ws = Workspace(name: "My Project")
        #expect(ws.name == "My Project")
    }

    @Test func roundTripWithIdAndName() throws {
        let ws = Workspace(name: "Test Project", gridLayout: .three_by_two)
        let data = try TestHelpers.encodeWorkspace(ws)
        let decoded = try TestHelpers.decodeWorkspace(from: data)
        #expect(decoded.id == ws.id)
        #expect(decoded.name == "Test Project")
    }

    @Test func legacyDecodeWithoutIdAndName() throws {
        let decoded = try TestHelpers.decodeWorkspace(fromJSON: """
        {"schemaVersion":1,"gridLayout":"2x2","cells":[]}
        """)
        #expect(!decoded.id.uuidString.isEmpty)
        #expect(decoded.name == "Default")
    }
}

@Suite("GridPreset Add Panel Tests")
struct GridPresetAddPanelTests {
    @Test func nextPresetForAddPanel() {
        #expect(GridPreset.one_by_one.nextPresetForAddPanel == .two_by_one)
        #expect(GridPreset.two_by_one.nextPresetForAddPanel == .two_by_two)
        #expect(GridPreset.one_by_two.nextPresetForAddPanel == .two_by_two)
        #expect(GridPreset.two_by_two.nextPresetForAddPanel == .three_by_two)
        #expect(GridPreset.three_by_two.nextPresetForAddPanel == .three_by_three)
        #expect(GridPreset.two_by_three.nextPresetForAddPanel == .three_by_three)
        #expect(GridPreset.three_by_three.nextPresetForAddPanel == nil)
    }

    @Test func isMaxPreset() {
        #expect(GridPreset.three_by_three.isMaxPreset == true)
        #expect(GridPreset.one_by_one.isMaxPreset == false)
        #expect(GridPreset.two_by_two.isMaxPreset == false)
        #expect(GridPreset.three_by_two.isMaxPreset == false)
    }
}

@Suite("Cell Codable Tests")
struct CellCodableTests {
    @Test func defaultWorkingDirectoryIsHome() {
        let cell = Cell()
        #expect(cell.workingDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test func roundTripWithWorkingDirectory() throws {
        let cell = Cell(workingDirectory: "/tmp/test")
        let data = try JSONEncoder().encode(cell)
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.workingDirectory == "/tmp/test")
    }

    @Test func decodesLegacyCellWithoutWorkingDirectory() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","label":"test","notes":""}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.label == "test")
        #expect(decoded.workingDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test func decodesTolerantlyWithMissingLabel() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","notes":"hi"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.label == "")
        #expect(decoded.notes == "hi")
    }

    @Test func defaultExplorerDirectoryIsEmpty() {
        let cell = Cell()
        #expect(cell.explorerDirectory == "")
        #expect(cell.explorerViewMode == .grid)
    }

    @Test func roundTripWithExplorerFields() throws {
        let cell = Cell(explorerDirectory: "/tmp/project", explorerViewMode: .list)
        let data = try JSONEncoder().encode(cell)
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.explorerDirectory == "/tmp/project")
        #expect(decoded.explorerViewMode == .list)
    }

    @Test func decodesLegacyCellWithoutExplorerFields() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","label":"test","notes":""}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.explorerDirectory == "")
        #expect(decoded.explorerViewMode == .grid)
    }
}
