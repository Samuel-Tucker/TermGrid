import Foundation
import AppKit

@MainActor
final class CommandRegistry {
    let commands: [AppCommand]

    init() {
        commands = Self.buildCommands()
    }

    func filter(query: String) -> [AppCommand] {
        guard !query.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    func availableCommands(for context: CommandContext) -> [AppCommand] {
        commands.filter { cmd in
            switch cmd.scope {
            case .global:
                return cmd.isAvailable(context)
            case .cell:
                return context.focusedCellID != nil && cmd.isAvailable(context)
            }
        }
    }

    private static func buildCommands() -> [AppCommand] {
        [
            AppCommand(
                id: "toggle-notes",
                title: "Toggle Notes",
                icon: "note.text",
                scope: .cell,
                action: { ctx in ctx.cellUIState?.showNotes.toggle() }
            ),
            AppCommand(
                id: "toggle-explorer",
                title: "Toggle File Explorer",
                icon: "doc.text.magnifyingglass",
                scope: .cell,
                action: { ctx in ctx.cellUIState?.showExplorer.toggle() }
            ),
            AppCommand(
                id: "set-terminal-directory",
                title: "Set Terminal Directory",
                icon: "folder",
                scope: .cell,
                action: { ctx in
                    guard let cellID = ctx.focusedCellID else { return }
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Select"
                    panel.message = "Choose a working directory for this terminal"
                    if panel.runModal() == .OK, let url = panel.url {
                        ctx.store.updateWorkingDirectory(url.path, for: cellID)
                        ctx.sessionManager.createSession(for: cellID, workingDirectory: url.path)
                    }
                }
            ),
            AppCommand(
                id: "set-explorer-directory",
                title: "Set Explorer Directory",
                icon: "folder.badge.gearshape",
                scope: .cell,
                action: { ctx in
                    guard let cellID = ctx.focusedCellID else { return }
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Select"
                    panel.message = "Choose a directory for the file explorer"
                    if panel.runModal() == .OK, let url = panel.url {
                        ctx.store.updateExplorerDirectory(url.path, for: cellID)
                    }
                }
            ),
            AppCommand(
                id: "new-file",
                title: "New File",
                icon: "doc.badge.plus",
                scope: .cell,
                isAvailable: { ctx in ctx.cellUIState?.showExplorer == true },
                action: { ctx in
                    NotificationCenter.default.post(
                        name: .commandPaletteNewFile,
                        object: ctx.focusedCellID
                    )
                }
            ),
            AppCommand(
                id: "new-folder",
                title: "New Folder",
                icon: "folder.badge.plus",
                scope: .cell,
                isAvailable: { ctx in ctx.cellUIState?.showExplorer == true },
                action: { ctx in
                    NotificationCenter.default.post(
                        name: .commandPaletteNewFolder,
                        object: ctx.focusedCellID
                    )
                }
            ),
            AppCommand(
                id: "toggle-hidden-files",
                title: "Show/Hide Hidden Files",
                icon: "eye",
                scope: .cell,
                isAvailable: { ctx in ctx.cellUIState?.showExplorer == true },
                action: { ctx in
                    NotificationCenter.default.post(
                        name: .commandPaletteToggleHidden,
                        object: ctx.focusedCellID
                    )
                }
            ),
            AppCommand(
                id: "switch-grid-layout",
                title: "Switch Grid Layout",
                icon: "square.grid.2x2",
                scope: .global,
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteSwitchGrid,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "toggle-api-locker",
                title: "Toggle API Locker",
                icon: "lock.fill",
                scope: .global,
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteToggleAPILocker,
                        object: nil
                    )
                }
            ),
        ]
    }
}

// MARK: - Notification Names for Command Palette Actions

extension Notification.Name {
    static let commandPaletteNewFile = Notification.Name("TermGrid.commandPalette.newFile")
    static let commandPaletteNewFolder = Notification.Name("TermGrid.commandPalette.newFolder")
    static let commandPaletteToggleHidden = Notification.Name("TermGrid.commandPalette.toggleHidden")
    static let commandPaletteSwitchGrid = Notification.Name("TermGrid.commandPalette.switchGrid")
    static let commandPaletteToggleAPILocker = Notification.Name("TermGrid.commandPalette.toggleAPILocker")
}
