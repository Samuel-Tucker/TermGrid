import Foundation

enum CommandScope {
    case global
    case cell
}

struct CommandContext {
    let focusedCellID: UUID?
    let cellUIState: CellUIState?
    let store: WorkspaceStore
    let sessionManager: TerminalSessionManager
    var collection: WorkspaceCollection? = nil
}

struct AppCommand: Identifiable {
    let id: String
    let title: String
    let icon: String
    let scope: CommandScope
    var isAvailable: (CommandContext) -> Bool = { _ in true }
    let action: (CommandContext) -> Void
}
