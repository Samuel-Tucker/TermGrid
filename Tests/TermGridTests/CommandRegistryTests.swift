@testable import TermGrid
import Testing
import Foundation

@Suite("CommandRegistry Tests")
@MainActor
struct CommandRegistryTests {

    @Test func registryContainsAllCommands() {
        let registry = CommandRegistry()
        #expect(registry.commands.count >= 13)
    }

    @Test func filterBySearchEmpty() {
        let registry = CommandRegistry()
        let results = registry.filter(query: "")
        #expect(results.count == registry.commands.count)
    }

    @Test func filterBySearchSubstring() {
        let registry = CommandRegistry()
        let results = registry.filter(query: "notes")
        #expect(results.contains(where: { $0.title.localizedCaseInsensitiveContains("notes") }))
        #expect(!results.isEmpty)
    }

    @Test func filterBySearchNoMatch() {
        let registry = CommandRegistry()
        let results = registry.filter(query: "xyznonexistent")
        #expect(results.isEmpty)
    }

    @Test func globalCommandsAlwaysAvailable() {
        let registry = CommandRegistry()
        let globals = registry.commands.filter { $0.scope == .global }
        #expect(!globals.isEmpty)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pm = PersistenceManager(directory: dir)
        let collection = WorkspaceCollection(
            workspaces: [Workspace(), Workspace(name: "Second")],
            persistence: pm
        )
        let context = CommandContext(
            focusedCellID: nil,
            cellUIState: nil,
            store: collection.activeStore,
            sessionManager: TerminalSessionManager(),
            collection: collection
        )
        for cmd in globals {
            #expect(cmd.isAvailable(context))
        }
    }

    @Test func cellCommandsAvailableWithFocusedCell() {
        let registry = CommandRegistry()
        let cellCmds = registry.commands.filter { $0.scope == .cell }
        #expect(!cellCmds.isEmpty)
    }
}
