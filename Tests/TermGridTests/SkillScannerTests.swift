@testable import TermGrid
import Foundation
import Testing

@Suite("SkillScanner Tests")
struct SkillScannerTests {

    // MARK: - Frontmatter Parsing

    @Test func simpleFrontmatter() {
        let md = """
        ---
        name: docker-cleanup
        description: Remove stopped containers
        ---
        # Docker Cleanup
        Run `docker system prune -af`
        """
        let parsed = SkillScanner.parseFrontmatter(md, fallbackName: "fallback")
        #expect(parsed.name == "docker-cleanup")
        #expect(parsed.description == "Remove stopped containers")
        #expect(parsed.body.contains("# Docker Cleanup"))
    }

    @Test func quotedDescription() {
        let md = """
        ---
        name: my-skill
        description: "A skill with: colons and stuff"
        ---
        Body here
        """
        let parsed = SkillScanner.parseFrontmatter(md, fallbackName: "fallback")
        #expect(parsed.name == "my-skill")
        #expect(parsed.description == "A skill with: colons and stuff")
    }

    @Test func extraKeysIgnored() {
        let md = """
        ---
        name: test-skill
        description: A test skill
        version: 2.0
        author: someone
        ---
        Content
        """
        let parsed = SkillScanner.parseFrontmatter(md, fallbackName: "fallback")
        #expect(parsed.name == "test-skill")
        #expect(parsed.description == "A test skill")
    }

    @Test func malformedFrontmatterFallback() {
        let md = """
        This has no frontmatter at all.
        Just some content.
        """
        let parsed = SkillScanner.parseFrontmatter(md, fallbackName: "dir-name")
        #expect(parsed.name == "dir-name")
        #expect(parsed.description == "")
        #expect(parsed.body == md)
    }

    @Test func emptyFrontmatter() {
        let md = """
        ---
        ---
        Body only
        """
        let parsed = SkillScanner.parseFrontmatter(md, fallbackName: "fallback")
        #expect(parsed.name == "fallback")
        #expect(parsed.description == "")
        #expect(parsed.body.contains("Body only"))
    }

    @Test func bodyExtraction() {
        let md = """
        ---
        name: test
        ---

        First line of body.
        Second line.
        """
        let parsed = SkillScanner.parseFrontmatter(md, fallbackName: "f")
        #expect(parsed.body.contains("First line of body."))
        #expect(parsed.body.contains("Second line."))
    }

    // MARK: - Categorization

    @Test func categorizesShell() {
        #expect(SkillScanner.categorize(name: "ffmpeg-helper", description: "Video processing") == .shell)
        #expect(SkillScanner.categorize(name: "bash-utils", description: "Shell utilities") == .shell)
        #expect(SkillScanner.categorize(name: "mlx-runner", description: "ML on Apple Silicon") == .shell)
    }

    @Test func categorizesCode() {
        #expect(SkillScanner.categorize(name: "electron-bridge", description: "IPC bridge") == .code)
        #expect(SkillScanner.categorize(name: "migration-helper", description: "DB migrations") == .code)
        #expect(SkillScanner.categorize(name: "test-runner", description: "Run tests") == .code)
    }

    @Test func categorizesPrompt() {
        #expect(SkillScanner.categorize(name: "gemini-advisor", description: "Advisory") == .prompt)
        #expect(SkillScanner.categorize(name: "youtube-seo", description: "Video SEO") == .prompt)
        #expect(SkillScanner.categorize(name: "red-team", description: "Security review") == .prompt)
    }

    @Test func categorizesCustomFallback() {
        #expect(SkillScanner.categorize(name: "dm-finder", description: "Find decision makers") == .custom)
        #expect(SkillScanner.categorize(name: "something-unique", description: "Totally unique") == .custom)
    }

    // MARK: - Dedup

    @Test func newSkillDetected() throws {
        let dir = try makeScanDir(skills: [
            ("my-skill", "---\nname: my-skill\ndescription: A skill\n---\n# Content\nHello")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = SkillScanner.scan(existingSkills: [], claudeDir: dir, codexDir: nil)
        #expect(result.newSkills.count == 1)
        #expect(result.newSkills.first?.name == "my-skill")
        #expect(result.newSkills.first?.origin == .claude)
        #expect(result.newSkills.first?.tags == ["claude-skill"])
    }

    @Test func identicalSkillSkipped() throws {
        let dir = try makeScanDir(skills: [
            ("my-skill", "---\nname: my-skill\ndescription: A skill\n---\n# Content\nHello")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let existing = [Skill(name: "my-skill", description: "A skill",
                              content: "# Content\nHello", category: .custom)]
        let result = SkillScanner.scan(existingSkills: existing, claudeDir: dir, codexDir: nil)
        #expect(result.newSkills.isEmpty)
        #expect(result.updatedSkills.isEmpty)
        #expect(result.skippedCount == 1)
    }

    @Test func updatedSkillDetected() throws {
        let dir = try makeScanDir(skills: [
            ("my-skill", "---\nname: my-skill\ndescription: Updated desc\n---\n# New Content\nChanged")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let existingID = UUID()
        let existingDate = Date(timeIntervalSince1970: 1000)
        let existing = [Skill(id: existingID, name: "my-skill", description: "Old desc",
                              content: "Old content", category: .custom, createdAt: existingDate)]
        let result = SkillScanner.scan(existingSkills: existing, claudeDir: dir, codexDir: nil)
        #expect(result.updatedSkills.count == 1)
        #expect(result.updatedSkills.first?.id == existingID)
        #expect(result.updatedSkills.first?.createdAt == existingDate)
        #expect(result.updatedSkills.first?.description == "Updated desc")
    }

    @Test func crossSourceClaudeWins() throws {
        let claudeDir = try makeScanDir(skills: [
            ("shared-skill", "---\nname: shared-skill\ndescription: Claude version\n---\nClaude body")
        ])
        let codexDir = try makeScanDir(skills: [
            ("shared-skill", "---\nname: shared-skill\ndescription: Codex version\n---\nCodex body")
        ])
        defer {
            try? FileManager.default.removeItem(at: claudeDir)
            try? FileManager.default.removeItem(at: codexDir)
        }

        let result = SkillScanner.scan(existingSkills: [], claudeDir: claudeDir, codexDir: codexDir)
        #expect(result.newSkills.count == 1)
        #expect(result.newSkills.first?.origin == .claude)
        #expect(result.skippedCount == 1)
    }

    // MARK: - Integration

    @Test func missingDirReturnsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let result = SkillScanner.scan(existingSkills: [], claudeDir: missing, codexDir: nil)
        #expect(result.newSkills.isEmpty)
        #expect(result.errors.isEmpty)
    }

    @Test func archivedDirsSkipped() throws {
        let dir = try makeScanDir(skills: [
            ("_archived", "---\nname: archived\n---\nContent"),
            ("good-skill", "---\nname: good-skill\ndescription: Good\n---\nContent here")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = SkillScanner.scan(existingSkills: [], claudeDir: dir, codexDir: nil)
        #expect(result.newSkills.count == 1)
        #expect(result.newSkills.first?.name == "good-skill")
    }

    @Test func missingSkillMdReportsError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-test-\(UUID().uuidString)")
        let skillDir = dir.appendingPathComponent("empty-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = SkillScanner.scan(existingSkills: [], claudeDir: dir, codexDir: nil)
        #expect(result.newSkills.isEmpty)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.contains("No SKILL.md") == true)
    }

    @Test func emptyContentSkipped() throws {
        let dir = try makeScanDir(skills: [
            ("empty-body", "---\nname: empty-body\ndescription: Nothing\n---\n")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = SkillScanner.scan(existingSkills: [], claudeDir: dir, codexDir: nil)
        #expect(result.newSkills.isEmpty)
        #expect(result.errors.count == 1)
    }

    @Test func codexOriginTagged() throws {
        let dir = try makeScanDir(skills: [
            ("codex-skill", "---\nname: codex-skill\ndescription: From codex\n---\nContent here")
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = SkillScanner.scan(existingSkills: [], claudeDir: nil, codexDir: dir)
        #expect(result.newSkills.count == 1)
        #expect(result.newSkills.first?.origin == .codex)
        #expect(result.newSkills.first?.tags == ["codex-skill"])
    }

    // MARK: - Helpers

    private func makeScanDir(skills: [(name: String, content: String)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-test-\(UUID().uuidString)")
        for (name, content) in skills {
            let skillDir = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            try content.write(to: skillDir.appendingPathComponent("SKILL.md"),
                              atomically: true, encoding: .utf8)
        }
        return dir
    }
}
