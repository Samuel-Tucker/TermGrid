// Sources/TermGrid/Models/CellUIState.swift
import Foundation
import Observation

@MainActor
@Observable
final class CellUIState {
    var showNotes: Bool = true
    var showExplorer: Bool = false
    var showGit: Bool = false
    /// Agent work shutter — dims terminal when agent is busy (opt-in)
    var shutterEnabled: Bool = false

    // MARK: - Phantom Compose
    var phantomComposeEnabled: Bool = true       // user pref (toggle via Cmd+Shift+P)
    var phantomComposeActive: Bool = false        // overlay visible?
    var phantomPendingCharacter: String? = nil    // first keystroke to inject
    var phantomComposeText: String = ""           // persists across dismiss/reactivate

    // MARK: - Compose History
    var composeHistoryActive: Bool = false        // history popup visible?
    var composeHistorySelectedIndex: Int = 0      // currently highlighted entry
}
