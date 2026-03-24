// Sources/TermGrid/Models/CellUIState.swift
import Foundation
import Observation

enum CellBodyMode {
    case terminal, explorer, projectNotes
}

/// Per-pane compose state so split terminals each get independent compose boxes.
@MainActor
@Observable
final class PaneComposeState {
    var phantomComposeActive: Bool = false
    var phantomPendingCharacter: String? = nil
    var phantomComposeText: String = ""
    var ghostText: String = ""
    var ghostFullToken: String = ""              // full predicted token (for feedback accuracy)
    var ghostAccepted: Bool = false              // was ghost accepted before send? (for learning)
    var slashCommands: [ComposeSlashCommand] = []
    var slashCommandSelectedIndex: Int = 0
    var composeHistoryActive: Bool = false
    var composeHistorySelectedIndex: Int = 0
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

    // MARK: - Phantom Compose (shared prefs)
    var phantomComposeEnabled: Bool = true       // user pref (toggle via Cmd+Shift+P)
    var ghostEnabled: Bool = true                // user pref (toggle via Cmd+Shift+P)
    var mlxEnabled: Bool = false                 // user pref (toggle AI autocomplete)

    /// Pending note path to open when switching to projectNotes bodyMode.
    var pendingNotePath: String? = nil

    // MARK: - Per-pane compose state
    let primaryPane = PaneComposeState()
    let splitPane = PaneComposeState()

    // MARK: - Legacy accessors (primary pane, for non-split callers)
    var phantomComposeActive: Bool {
        get { primaryPane.phantomComposeActive }
        set { primaryPane.phantomComposeActive = newValue }
    }
    var phantomPendingCharacter: String? {
        get { primaryPane.phantomPendingCharacter }
        set { primaryPane.phantomPendingCharacter = newValue }
    }
    var phantomComposeText: String {
        get { primaryPane.phantomComposeText }
        set { primaryPane.phantomComposeText = newValue }
    }
    var ghostText: String {
        get { primaryPane.ghostText }
        set { primaryPane.ghostText = newValue }
    }
    var ghostFullToken: String {
        get { primaryPane.ghostFullToken }
        set { primaryPane.ghostFullToken = newValue }
    }
    var ghostAccepted: Bool {
        get { primaryPane.ghostAccepted }
        set { primaryPane.ghostAccepted = newValue }
    }
    var composeHistoryActive: Bool {
        get { primaryPane.composeHistoryActive }
        set { primaryPane.composeHistoryActive = newValue }
    }
    var composeHistorySelectedIndex: Int {
        get { primaryPane.composeHistorySelectedIndex }
        set { primaryPane.composeHistorySelectedIndex = newValue }
    }
}
