import Foundation

struct SkillScanner {
    struct ScanResult: Identifiable {
        let id = UUID()
        var newSkills: [Skill] = []
        var updatedSkills: [Skill] = []
        var skippedCount: Int = 0
        var errors: [String] = []
    }

    // MARK: - Public API

    static func scan(existingSkills: [Skill]) async -> ScanResult {
        var result = ScanResult()
        var seen: Set<String> = []

        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills")
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/skills")

        scanDirectory(claudeDir, origin: .claude, existing: existingSkills,
                      seen: &seen, result: &result)
        scanDirectory(codexDir, origin: .codex, existing: existingSkills,
                      seen: &seen, result: &result)

        return result
    }

    // Testable entry point with explicit paths
    static func scan(existingSkills: [Skill], claudeDir: URL?, codexDir: URL?) -> ScanResult {
        var result = ScanResult()
        var seen: Set<String> = []

        if let dir = claudeDir {
            scanDirectory(dir, origin: .claude, existing: existingSkills,
                          seen: &seen, result: &result)
        }
        if let dir = codexDir {
            scanDirectory(dir, origin: .codex, existing: existingSkills,
                          seen: &seen, result: &result)
        }

        return result
    }

    // MARK: - Directory scanning

    private static func scanDirectory(_ dir: URL, origin: SkillOrigin,
                                       existing: [Skill], seen: inout Set<String>,
                                       result: inout ScanResult) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return }

        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let dirName = entry.lastPathComponent
            guard dirName.first != "_" else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let skillFile = entry.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else {
                result.errors.append("No SKILL.md in \(dirName)")
                continue
            }

            guard let raw = try? String(contentsOf: skillFile, encoding: .utf8) else {
                result.errors.append("Cannot read SKILL.md in \(dirName)")
                continue
            }

            let parsed = parseFrontmatter(raw, fallbackName: dirName)
            let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                result.errors.append("Empty content in \(dirName)")
                continue
            }

            let normalizedName = (parsed.name).lowercased().trimmingCharacters(in: .whitespaces)
            guard !seen.contains(normalizedName) else {
                result.skippedCount += 1
                continue
            }
            seen.insert(normalizedName)

            let tag = origin == .claude ? "claude-skill" : "codex-skill"
            let category = categorize(name: parsed.name, description: parsed.description)
            let skill = Skill(
                name: parsed.name,
                description: parsed.description,
                content: body,
                category: category,
                tags: [tag],
                origin: origin
            )

            if let idx = existing.firstIndex(where: { $0.name.lowercased().trimmingCharacters(in: .whitespaces) == normalizedName }) {
                let ex = existing[idx]
                if ex.content == body && ex.description == parsed.description {
                    result.skippedCount += 1
                } else {
                    var updated = skill
                    updated.id = ex.id
                    updated.createdAt = ex.createdAt
                    result.updatedSkills.append(updated)
                }
            } else {
                result.newSkills.append(skill)
            }
        }
    }

    // MARK: - Frontmatter parser

    struct ParsedSkill {
        var name: String
        var description: String
        var body: String
    }

    static func parseFrontmatter(_ raw: String, fallbackName: String) -> ParsedSkill {
        let lines = raw.components(separatedBy: "\n")
        guard let firstDash = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ParsedSkill(name: fallbackName, description: "", body: raw)
        }

        let afterFirst = lines.index(after: firstDash)
        guard afterFirst < lines.count else {
            return ParsedSkill(name: fallbackName, description: "", body: raw)
        }

        guard let secondDash = lines[afterFirst...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ParsedSkill(name: fallbackName, description: "", body: raw)
        }

        let frontmatterLines = lines[afterFirst..<secondDash]
        var name = fallbackName
        var description = ""

        for line in frontmatterLines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            switch key {
            case "name": name = value
            case "description": description = value
            default: break
            }
        }

        let bodyStart = lines.index(after: secondDash)
        let body = bodyStart < lines.count
            ? lines[bodyStart...].joined(separator: "\n")
            : ""

        return ParsedSkill(name: name, description: description, body: body)
    }

    // MARK: - Categorization

    static func categorize(name: String, description: String) -> SkillCategory {
        let text = "\(name) \(description)".lowercased()

        // Priority 1: Prompt — advisory, orchestration, social/content, review tools
        let promptKeywords = ["advisor", "advisory", "orchestrat", "conductor", "agent",
                              "review", "plan-review", "red-team", "bug-hunt",
                              "text-to-speech", "tiktok", "twitter", "youtube",
                              "seo", "caption"]
        if promptKeywords.contains(where: { text.contains($0) }) { return .prompt }

        // Priority 2: Shell — CLI tools, terminal, media processing, runtimes
        let shellKeywords = ["ffmpeg", "bash", "shell", "terminal", "scraping",
                             "node", "mlx", "cheerio", "deploy", "wsl", "xterm", "pty"]
        if shellKeywords.contains(where: { text.contains($0) }) { return .shell }

        // Priority 3: Code — dev tooling, architecture, testing
        let codeKeywords = ["electron", "test", "lifecycle", "hardening", "safety", "bridge",
                            "contract", "invariant", "layout", "state", "ipc", "renderer",
                            "repository", "neon", "migration"]
        if codeKeywords.contains(where: { text.contains($0) }) { return .code }

        return .custom
    }
}
