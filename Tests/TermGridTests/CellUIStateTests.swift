// Tests/TermGridTests/CellUIStateTests.swift
@testable import TermGrid
import Testing

@Suite("CellUIState Tests")
@MainActor
struct CellUIStateTests {

    @Test func defaultValues() {
        let state = CellUIState()
        #expect(state.scratchPadVisible == true)
        #expect(state.bodyMode == .terminal)
        #expect(state.showGit == false)
        // Backward-compat computed properties
        #expect(state.showNotes == true)
        #expect(state.showExplorer == false)
    }

    @Test func toggleScratchPad() {
        let state = CellUIState()
        state.scratchPadVisible = false
        #expect(state.scratchPadVisible == false)
        #expect(state.showNotes == false)
    }

    @Test func bodyModeExplorer() {
        let state = CellUIState()
        state.bodyMode = .explorer
        #expect(state.showExplorer == true)
        state.bodyMode = .terminal
        #expect(state.showExplorer == false)
    }

    @Test func bodyModeProjectNotes() {
        let state = CellUIState()
        state.bodyMode = .projectNotes
        #expect(state.showExplorer == false)
        #expect(state.bodyMode == .projectNotes)
    }

    @Test func toggleShowGit() {
        let state = CellUIState()
        state.showGit = true
        #expect(state.showGit == true)
    }
}
