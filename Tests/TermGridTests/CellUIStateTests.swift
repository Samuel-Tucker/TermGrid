// Tests/TermGridTests/CellUIStateTests.swift
@testable import TermGrid
import Testing

@Suite("CellUIState Tests")
@MainActor
struct CellUIStateTests {

    @Test func defaultValues() {
        let state = CellUIState()
        #expect(state.showNotes == true)
        #expect(state.showExplorer == false)
        #expect(state.showGit == false)
    }

    @Test func toggleShowNotes() {
        let state = CellUIState()
        state.showNotes = false
        #expect(state.showNotes == false)
    }

    @Test func toggleShowExplorer() {
        let state = CellUIState()
        state.showExplorer = true
        #expect(state.showExplorer == true)
    }

    @Test func toggleShowGit() {
        let state = CellUIState()
        state.showGit = true
        #expect(state.showGit == true)
    }
}
