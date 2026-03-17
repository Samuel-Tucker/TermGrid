// Sources/TermGrid/Models/CellUIState.swift
import Foundation
import Observation

@MainActor
@Observable
final class CellUIState {
    var showNotes: Bool = true
    var showExplorer: Bool = false
    var showGit: Bool = false
}
