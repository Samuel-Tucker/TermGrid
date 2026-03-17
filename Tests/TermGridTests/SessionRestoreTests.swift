// Tests/TermGridTests/SessionRestoreTests.swift
@testable import TermGrid
import Testing
import Foundation

@Suite("Session Restore Tests")
@MainActor
struct SessionRestoreTests {

    @Test func cellDefaultSplitDirectionIsNil() {
        let cell = Cell()
        #expect(cell.splitDirection == nil)
    }

    @Test func cellDefaultShowExplorerIsFalse() {
        let cell = Cell()
        #expect(cell.showExplorer == false)
    }

    @Test func cellSplitDirectionEncodes() throws {
        var cell = Cell()
        cell.splitDirection = "horizontal"
        cell.showExplorer = true
        let data = try JSONEncoder().encode(cell)
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.splitDirection == "horizontal")
        #expect(decoded.showExplorer == true)
    }

    @Test func cellSplitDirectionNilEncodes() throws {
        let cell = Cell()
        let data = try JSONEncoder().encode(cell)
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.splitDirection == nil)
        #expect(decoded.showExplorer == false)
    }

    @Test func cellDecodesWithoutNewFieldsGracefully() throws {
        let json = """
        {"id":"\(UUID().uuidString)","label":"Test","notes":"","workingDirectory":"/tmp","terminalLabel":"","splitTerminalLabel":"","explorerDirectory":"","explorerViewMode":"grid"}
        """
        let data = json.data(using: .utf8)!
        let cell = try JSONDecoder().decode(Cell.self, from: data)
        #expect(cell.splitDirection == nil)
        #expect(cell.showExplorer == false)
    }
}
