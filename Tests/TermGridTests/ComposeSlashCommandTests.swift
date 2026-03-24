@testable import TermGrid
import Foundation
import Testing

@Suite("Compose Slash Command Tests")
struct ComposeSlashCommandTests {

    @Test func activeQueryUsesCurrentLine() {
        let text = """
        explain this change
          /mo
        """

        #expect(ComposeSlashCommandCatalog.activeQuery(in: text) == "/mo")
    }

    @Test func codexSuggestionsFilterByPrefix() {
        let suggestions = ComposeSlashCommandCatalog.suggestions(
            for: "/mo",
            agentType: .codex,
            workingDirectory: nil
        )

        #expect(suggestions.contains(where: { $0.name == "model" }))
        #expect(!suggestions.contains(where: { $0.name == "clear" }))
    }

    @Test func applyReplacesCurrentSlashToken() {
        let updated = ComposeSlashCommandCatalog.apply(
            ComposeSlashCommand(name: "model", description: "", source: .builtin),
            to: "  /mo"
        )

        #expect(updated == "  /model ")
    }

    @Test func claudeCommandsIncludeProjectAndUserMarkdownCommands() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("slash-commands-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let userCommands = home.appendingPathComponent(".claude/commands", isDirectory: true)
        let projectCommands = project.appendingPathComponent(".claude/commands/release", isDirectory: true)

        try FileManager.default.createDirectory(at: userCommands, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectCommands, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        ---
        description: User level command
        ---
        Body
        """.write(to: userCommands.appendingPathComponent("ship.md"), atomically: true, encoding: .utf8)

        try """
        # Release
        Prepare release notes
        """.write(to: projectCommands.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let commands = ComposeSlashCommandCatalog.commands(
            for: .claudeCode,
            workingDirectory: project.path,
            homeDirectory: home
        )

        #expect(commands.contains(where: { $0.name == "ship" && $0.source == .user }))
        #expect(commands.contains(where: { $0.name == "release:notes" && $0.source == .project }))
        #expect(commands.contains(where: { $0.name == "help" && $0.source == .builtin }))
    }

    @Test func unknownAgentReturnsNoSuggestions() {
        let suggestions = ComposeSlashCommandCatalog.suggestions(
            for: "/mo",
            agentType: .unknown,
            workingDirectory: nil
        )

        #expect(suggestions.isEmpty)
    }
}
