@testable import TermGrid
import Foundation
import Testing

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
}
