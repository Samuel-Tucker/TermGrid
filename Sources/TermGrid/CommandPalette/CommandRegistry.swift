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
                id: "toggle-scratch-pad",
                title: "Toggle Scratch Pad",
                icon: "note.text",
                scope: .cell,
                action: { ctx in ctx.cellUIState?.scratchPadVisible.toggle() }
            ),
            AppCommand(
                id: "toggle-explorer",
                title: "Toggle File Explorer",
                icon: "doc.text.magnifyingglass",
                scope: .cell,
                action: { ctx in
                    guard let ui = ctx.cellUIState else { return }
                    ui.bodyMode = ui.bodyMode == .explorer ? .terminal : .explorer
                }
            ),
            AppCommand(
                id: "toggle-project-notes",
                title: "Toggle Project Notes",
                icon: "folder.badge.questionmark",
                scope: .cell,
                action: { ctx in
                    guard let ui = ctx.cellUIState else { return }
                    ui.bodyMode = ui.bodyMode == .projectNotes ? .terminal : .projectNotes
                }
            ),
            AppCommand(
                id: "toggle-agent-shutter",
                title: "Toggle Agent Shutter",
                icon: "gearshape.2",
                scope: .cell,
                action: { ctx in ctx.cellUIState?.shutterEnabled.toggle() }
            ),
            AppCommand(
                id: "toggle-ghost-autocomplete",
                title: "Toggle Ghost Autocomplete",
                icon: "text.insert",
                scope: .cell,
                action: { ctx in ctx.cellUIState?.ghostEnabled.toggle() }
            ),
            AppCommand(
                id: "toggle-git-sidebar",
                title: "Toggle Git Sidebar",
                icon: "arrow.triangle.branch",
                scope: .cell,
                action: { ctx in ctx.cellUIState?.showGit.toggle() }
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
                isAvailable: { ctx in ctx.cellUIState?.bodyMode == .explorer },
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
                isAvailable: { ctx in ctx.cellUIState?.bodyMode == .explorer },
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
                isAvailable: { ctx in ctx.cellUIState?.bodyMode == .explorer },
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
                id: "toggle-skills",
                title: "Toggle Skills",
                icon: "book",
                scope: .global,
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteToggleSkills,
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
            AppCommand(
                id: "toggle-phantom-compose",
                title: "Toggle Phantom Compose",
                icon: "text.cursor",
                scope: .cell,
                action: { ctx in
                    ctx.cellUIState?.phantomComposeEnabled.toggle()
                    if !(ctx.cellUIState?.phantomComposeEnabled ?? true) {
                        ctx.cellUIState?.phantomComposeActive = false
                    }
                }
            ),
            AppCommand(
                id: "compose-history",
                title: "Compose History (^R)",
                icon: "clock.arrow.circlepath",
                scope: .cell,
                isAvailable: { ctx in ctx.cellUIState?.phantomComposeEnabled == true },
                action: { ctx in
                    ctx.cellUIState?.composeHistoryActive = true
                    if !(ctx.cellUIState?.phantomComposeActive ?? false) {
                        ctx.cellUIState?.phantomComposeActive = true
                    }
                }
            ),
            AppCommand(
                id: "quick-terminal",
                title: "Quick Terminal (⌘⇧F)",
                icon: "pip",
                scope: .global,
                action: { _ in
                    NotificationCenter.default.post(
                        name: .toggleFloatingPane,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "new-workspace",
                title: "New Workspace (⌘T)",
                icon: "plus.rectangle",
                scope: .global,
                isAvailable: { ctx in
                    (ctx.collection?.workspaces.count ?? 0) < WorkspaceCollection.maxWorkspaces
                },
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteNewWorkspace,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "close-workspace",
                title: "Close Workspace (⌘⇧W)",
                icon: "xmark.rectangle",
                scope: .global,
                isAvailable: { ctx in (ctx.collection?.workspaces.count ?? 0) > 1 },
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteCloseWorkspace,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "rename-workspace",
                title: "Rename Workspace",
                icon: "pencil",
                scope: .global,
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteRenameWorkspace,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "next-workspace",
                title: "Next Workspace (⌘⇧])",
                icon: "arrow.right.square",
                scope: .global,
                isAvailable: { ctx in (ctx.collection?.workspaces.count ?? 0) > 1 },
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteNextWorkspace,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "prev-workspace",
                title: "Previous Workspace (⌘⇧[)",
                icon: "arrow.left.square",
                scope: .global,
                isAvailable: { ctx in (ctx.collection?.workspaces.count ?? 0) > 1 },
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPalettePrevWorkspace,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "swap-panel-left",
                title: "Swap Panel Left",
                icon: "arrow.left.arrow.right",
                scope: .cell,
                isAvailable: { ctx in (ctx.store.workspace.visibleCells.count) > 1 },
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteSwapDirection,
                        object: "left"
                    )
                }
            ),
            AppCommand(
                id: "swap-panel-right",
                title: "Swap Panel Right",
                icon: "arrow.left.arrow.right",
                scope: .cell,
                isAvailable: { ctx in (ctx.store.workspace.visibleCells.count) > 1 },
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteSwapDirection,
                        object: "right"
                    )
                }
            ),
            AppCommand(
                id: "add-panel",
                title: "Add Panel (⌘⇧N)",
                icon: "plus.rectangle",
                scope: .global,
                isAvailable: { ctx in ctx.store.canAddPanel },
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteAddPanel,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "popout-reader",
                title: "Popout Terminal Output (⌘⇧E)",
                icon: "arrow.up.left.and.arrow.down.right",
                scope: .cell,
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPalettePopoutReader,
                        object: nil
                    )
                }
            ),
        ]
    }
}

// MARK: - Notification Names for Command Palette Actions

extension Notification.Name {
    static let toggleCommandPalette = Notification.Name("TermGrid.toggleCommandPalette")
    static let commandPaletteNewFile = Notification.Name("TermGrid.commandPalette.newFile")
    static let commandPaletteNewFolder = Notification.Name("TermGrid.commandPalette.newFolder")
    static let commandPaletteToggleHidden = Notification.Name("TermGrid.commandPalette.toggleHidden")
    static let commandPaletteSwitchGrid = Notification.Name("TermGrid.commandPalette.switchGrid")
    static let commandPaletteToggleAPILocker = Notification.Name("TermGrid.commandPalette.toggleAPILocker")
    static let toggleFloatingPane = Notification.Name("TermGrid.toggleFloatingPane")
    static let commandPaletteNewWorkspace = Notification.Name("TermGrid.commandPalette.newWorkspace")
    static let commandPaletteCloseWorkspace = Notification.Name("TermGrid.commandPalette.closeWorkspace")
    static let commandPaletteRenameWorkspace = Notification.Name("TermGrid.commandPalette.renameWorkspace")
    static let commandPaletteNextWorkspace = Notification.Name("TermGrid.commandPalette.nextWorkspace")
    static let commandPalettePrevWorkspace = Notification.Name("TermGrid.commandPalette.prevWorkspace")
    static let commandPaletteToggleSkills = Notification.Name("TermGrid.commandPalette.toggleSkills")
    static let commandPaletteSwapDirection = Notification.Name("TermGrid.commandPalette.swapDirection")
    static let commandPaletteAddPanel = Notification.Name("TermGrid.commandPalette.addPanel")
    static let commandPalettePopoutReader = Notification.Name("TermGrid.commandPalette.popoutReader")
}
