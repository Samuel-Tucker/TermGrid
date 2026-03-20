@testable import TermGrid
import Foundation
import Testing

@Suite("SkillsManager Tests")
@MainActor
struct SkillsManagerTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermGridSkillsTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func addAndList() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        let skill = Skill(name: "Test", content: "echo hi", category: .shell)
        manager.addSkill(skill)
        #expect(manager.skills.count == 1)
        #expect(manager.skills.first?.name == "Test")
    }

    @Test func updateSkill() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        var skill = Skill(name: "Original", content: "echo a", category: .shell)
        manager.addSkill(skill)
        skill.name = "Updated"
        skill.content = "echo b"
        manager.updateSkill(skill)
        #expect(manager.skills.count == 1)
        #expect(manager.skills.first?.name == "Updated")
        #expect(manager.skills.first?.content == "echo b")
    }

    @Test func removeSkill() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        let skill = Skill(name: "ToDelete", content: "rm -rf", category: .shell)
        manager.addSkill(skill)
        #expect(manager.skills.count == 1)
        manager.removeSkill(id: skill.id)
        #expect(manager.skills.isEmpty)
    }

    @Test func persistenceRoundTrip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager1 = SkillsManager(directory: dir)
        manager1.addSkill(Skill(name: "Persisted", content: "data", category: .prompt, tags: ["test"]))
        // Create a new manager reading from the same directory
        let manager2 = SkillsManager(directory: dir)
        #expect(manager2.skills.count == 1)
        #expect(manager2.skills.first?.name == "Persisted")
        #expect(manager2.skills.first?.tags == ["test"])
    }

    @Test func loadReturnsEmptyWhenMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        #expect(manager.skills.isEmpty)
    }

    @Test func filterByCategory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        manager.addSkill(Skill(name: "Shell1", content: "ls", category: .shell))
        manager.addSkill(Skill(name: "Code1", content: "func", category: .code))
        manager.addSkill(Skill(name: "Shell2", content: "pwd", category: .shell))
        let shellOnly = manager.filtered(by: .shell, query: "")
        #expect(shellOnly.count == 2)
        #expect(shellOnly.allSatisfy { $0.category == .shell })
    }

    @Test func filterBySearchQuery() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        manager.addSkill(Skill(name: "Docker Cleanup", content: "docker prune", category: .shell))
        manager.addSkill(Skill(name: "Git Reset", content: "git reset --hard", category: .shell))
        let results = manager.filtered(by: nil, query: "docker")
        #expect(results.count == 1)
        #expect(results.first?.name == "Docker Cleanup")
    }

    @Test func searchMatchesTags() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        manager.addSkill(Skill(name: "Something", content: "code", category: .code, tags: ["kubernetes", "k8s"]))
        manager.addSkill(Skill(name: "Other", content: "other", category: .code, tags: ["python"]))
        let results = manager.filtered(by: nil, query: "kubernetes")
        #expect(results.count == 1)
        #expect(results.first?.name == "Something")
    }

    @Test func importOrUpdateAddsNew() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        let skill = Skill(name: "Imported", content: "content", category: .shell, origin: .claude)
        manager.importOrUpdate([skill])
        #expect(manager.skills.count == 1)
        #expect(manager.skills.first?.name == "Imported")
        #expect(manager.skills.first?.origin == .claude)
    }

    @Test func importOrUpdateUpdatesExisting() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        let original = Skill(name: "Skill", content: "old", category: .shell)
        manager.addSkill(original)
        let originalID = manager.skills.first!.id

        let updated = Skill(name: "Skill", content: "new content", category: .code, origin: .codex)
        manager.importOrUpdate([updated])
        #expect(manager.skills.count == 1)
        #expect(manager.skills.first?.id == originalID)
        #expect(manager.skills.first?.content == "new content")
    }

    @Test func importOrUpdateBatch() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SkillsManager(directory: dir)
        let skills = [
            Skill(name: "A", content: "a", category: .shell, origin: .claude),
            Skill(name: "B", content: "b", category: .code, origin: .codex),
        ]
        manager.importOrUpdate(skills)
        #expect(manager.skills.count == 2)
    }
}
