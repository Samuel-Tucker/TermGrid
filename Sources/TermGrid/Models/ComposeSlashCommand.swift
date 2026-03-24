import Foundation

struct ComposeSlashCommand: Identifiable, Hashable {
    enum Source: String, Hashable {
        case builtin
        case project
        case user
    }

    let name: String
    let description: String
    let source: Source

    var id: String { "\(source.rawValue):\(name)" }
    var trigger: String { "/\(name)" }
}

enum ComposeSlashCommandCatalog {
    static func suggestions(
        for text: String,
        agentType: AgentType?,
        workingDirectory: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ComposeSlashCommand] {
        guard let query = activeQuery(in: text) else { return [] }
        let needle = String(query.dropFirst()).lowercased()
        let commands = commands(for: agentType, workingDirectory: workingDirectory, homeDirectory: homeDirectory)

        return commands.filter { command in
            needle.isEmpty || command.name.lowercased().hasPrefix(needle)
        }
    }

    static func activeQuery(in text: String) -> String? {
        let line = currentLine(in: text)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        guard let token = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        let query = String(token)
        return query.isEmpty ? nil : query
    }

    static func apply(_ command: ComposeSlashCommand, to text: String) -> String {
        let lineStart = text.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let line = String(text[lineStart...])
        let leadingWhitespaceEnd = line.firstIndex(where: { !$0.isWhitespace }) ?? line.endIndex
        let trimmed = String(line[leadingWhitespaceEnd...])

        guard trimmed.hasPrefix("/") else { return text }

        let tokenEndOffset = trimmed.firstIndex(where: \.isWhitespace) ?? trimmed.endIndex
        let trailing = trimmed[tokenEndOffset...]
        let suffix = trailing.isEmpty ? " " : String(trailing)
        let replacementLine = String(line[..<leadingWhitespaceEnd]) + command.trigger + suffix
        return String(text[..<lineStart]) + replacementLine
    }

    static func commands(
        for agentType: AgentType?,
        workingDirectory: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ComposeSlashCommand] {
        switch agentType {
        case .claudeCode:
            return dedupe(
                scanClaudeCommands(workingDirectory: workingDirectory, homeDirectory: homeDirectory)
                + claudeBuiltins
            )
        case .codex:
            return codexBuiltins
        default:
            return []
        }
    }

    private static func dedupe(_ commands: [ComposeSlashCommand]) -> [ComposeSlashCommand] {
        var seen = Set<String>()
        var ordered: [ComposeSlashCommand] = []

        for command in commands {
            guard seen.insert(command.name).inserted else { continue }
            ordered.append(command)
        }

        return ordered
    }

    private static func currentLine(in text: String) -> String {
        if let newlineIndex = text.lastIndex(of: "\n") {
            return String(text[text.index(after: newlineIndex)...])
        }
        return text
    }

    private static func scanClaudeCommands(
        workingDirectory: String?,
        homeDirectory: URL
    ) -> [ComposeSlashCommand] {
        var commands: [ComposeSlashCommand] = []
        let fm = FileManager.default

        let userDir = homeDirectory.appendingPathComponent(".claude/commands", isDirectory: true)
        commands += scanMarkdownCommands(in: userDir, source: .user, fileManager: fm)

        if let workingDirectory {
            let projectDir = URL(fileURLWithPath: workingDirectory)
                .appendingPathComponent(".claude/commands", isDirectory: true)
            commands = scanMarkdownCommands(in: projectDir, source: .project, fileManager: fm) + commands
        }

        return commands
    }

    private static func scanMarkdownCommands(
        in directory: URL,
        source: ComposeSlashCommand.Source,
        fileManager: FileManager
    ) -> [ComposeSlashCommand] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var commands: [ComposeSlashCommand] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }

            let name = commandName(for: fileURL, root: directory)
            guard !name.isEmpty else { continue }

            let markdown = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            commands.append(
                ComposeSlashCommand(
                    name: name,
                    description: commandDescription(from: markdown),
                    source: source
                )
            )
        }

        return commands.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func commandName(for fileURL: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        guard fileComponents.count >= rootComponents.count else { return "" }
        let relativeComponents = fileComponents.dropFirst(rootComponents.count)
        let joined = relativeComponents.joined(separator: "/")
        let noExtension = (joined as NSString).deletingPathExtension
        return noExtension
            .split(separator: "/")
            .map(String.init)
            .joined(separator: ":")
    }

    private static func commandDescription(from markdown: String) -> String {
        if let frontmatter = frontmatterDescription(from: markdown), !frontmatter.isEmpty {
            return frontmatter
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !line.hasPrefix("---"), !line.hasPrefix("#") else { continue }
            return line
        }

        return ""
    }

    private static func frontmatterDescription(from markdown: String) -> String? {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return nil }
        let separator = markdown.contains("\r\n") ? "\r\n" : "\n"
        let parts = markdown.components(separatedBy: separator)
        guard parts.count >= 3, parts[0] == "---" else { return nil }

        for line in parts.dropFirst() {
            if line == "---" { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("description:") else { continue }
            let value = trimmed.dropFirst("description:".count)
                .trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: "\"'")))
            return value
        }

        return nil
    }

    private static let claudeBuiltins: [ComposeSlashCommand] = [
        .init(name: "add-dir", description: "Add an additional working directory", source: .builtin),
        .init(name: "agents", description: "Manage custom AI subagents", source: .builtin),
        .init(name: "bug", description: "Report a bug to Anthropic", source: .builtin),
        .init(name: "clear", description: "Clear conversation history", source: .builtin),
        .init(name: "compact", description: "Compact the conversation", source: .builtin),
        .init(name: "config", description: "View or modify Claude Code config", source: .builtin),
        .init(name: "cost", description: "Show token and usage stats", source: .builtin),
        .init(name: "doctor", description: "Check installation health", source: .builtin),
        .init(name: "help", description: "Show usage help", source: .builtin),
        .init(name: "init", description: "Initialize the project with CLAUDE.md guidance", source: .builtin),
        .init(name: "login", description: "Switch Anthropic accounts", source: .builtin),
        .init(name: "logout", description: "Sign out of Claude Code", source: .builtin),
        .init(name: "mcp", description: "Manage MCP servers and OAuth auth", source: .builtin),
        .init(name: "model", description: "Choose the active model", source: .builtin),
        .init(name: "plan", description: "Enter or drive plan mode", source: .builtin),
        .init(name: "resume", description: "Resume a previous session", source: .builtin),
        .init(name: "theme", description: "Change UI theme", source: .builtin),
        .init(name: "voice", description: "Toggle voice mode", source: .builtin),
    ]

    // Derived from the installed Codex CLI 0.116.0 strings table and UI prompts.
    private static let codexBuiltins: [ComposeSlashCommand] = [
        .init(name: "approvals", description: "Choose what Codex is allowed to do", source: .builtin),
        .init(name: "apps", description: "Manage installed apps and connectors", source: .builtin),
        .init(name: "clear", description: "Clear the terminal and start a new chat", source: .builtin),
        .init(name: "collab", description: "Change collaboration mode", source: .builtin),
        .init(name: "compact", description: "Summarize conversation to free context", source: .builtin),
        .init(name: "copy", description: "Copy the latest Codex output to the clipboard", source: .builtin),
        .init(name: "debug-config", description: "Show config layers and requirement sources", source: .builtin),
        .init(name: "diff", description: "Show git diff including untracked files", source: .builtin),
        .init(name: "feedback", description: "Send logs and feedback to maintainers", source: .builtin),
        .init(name: "fork", description: "Fork the current chat into a new thread", source: .builtin),
        .init(name: "init", description: "Create an AGENTS.md contributor guide", source: .builtin),
        .init(name: "logout", description: "Sign out of Codex", source: .builtin),
        .init(name: "mcp", description: "List configured MCP tools", source: .builtin),
        .init(name: "model", description: "Choose the active model and reasoning effort", source: .builtin),
        .init(name: "new", description: "Start a new chat during a conversation", source: .builtin),
        .init(name: "personality", description: "Customize how Codex communicates", source: .builtin),
        .init(name: "plan", description: "Switch to Plan mode", source: .builtin),
        .init(name: "ps", description: "List background terminals", source: .builtin),
        .init(name: "rename", description: "Rename the current thread", source: .builtin),
        .init(name: "resume", description: "Resume a saved chat", source: .builtin),
        .init(name: "review", description: "Review current changes and find issues", source: .builtin),
        .init(name: "rollout", description: "Print the rollout file path", source: .builtin),
        .init(name: "sandbox-add-read-dir", description: "Allow sandbox read access to a directory", source: .builtin),
        .init(name: "setup-default-sandbox", description: "Set up the elevated agent sandbox", source: .builtin),
        .init(name: "skills", description: "List available skills", source: .builtin),
        .init(name: "status", description: "Show model, approvals, and token usage", source: .builtin),
        .init(name: "statusline", description: "Configure status line items", source: .builtin),
        .init(name: "subagents", description: "Manage subagents", source: .builtin),
        .init(name: "test-approval", description: "Test approval requests", source: .builtin),
        .init(name: "voice", description: "Toggle realtime voice mode", source: .builtin),
    ]
}
