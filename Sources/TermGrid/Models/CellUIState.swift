// Sources/TermGrid/Models/CellUIState.swift
import Foundation
import Observation

enum CellBodyMode {
    case terminal, explorer, projectNotes
}

@MainActor
@Observable
final class CellUIState {
    var scratchPadVisible: Bool = true
    var bodyMode: CellBodyMode = .terminal
    var showGit: Bool = false
    /// Agent work shutter — dims terminal when agent is busy (opt-in)
    var shutterEnabled: Bool = false

    // MARK: - Backward-Compat Computed Properties
    var showNotes: Bool { scratchPadVisible }
    var showExplorer: Bool { bodyMode == .explorer }

    // MARK: - Phantom Compose
    var phantomComposeEnabled: Bool = true       // user pref (toggle via Cmd+Shift+P)
    var phantomComposeActive: Bool = false        // overlay visible?
    var phantomPendingCharacter: String? = nil    // first keystroke to inject
    var phantomComposeText: String = ""           // persists across dismiss/reactivate

    // MARK: - Ghost Autocomplete
    var ghostText: String = ""                   // current ghost suggestion
    var ghostEnabled: Bool = true                // user pref (toggle via Cmd+Shift+P)

    // MARK: - Compose History
    var composeHistoryActive: Bool = false        // history popup visible?
    var composeHistorySelectedIndex: Int = 0      // currently highlighted entry
}
