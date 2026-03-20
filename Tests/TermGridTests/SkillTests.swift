@testable import TermGrid
import Foundation
import Testing

@Suite("Skill Model Tests")
struct SkillTests {
    @Test func codableRoundTrip() throws {
        let skill = Skill(
            name: "Docker Cleanup",
            description: "Remove all stopped containers",
            content: "docker system prune -af",
            category: .shell,
            tags: ["docker", "cleanup"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Skill.self, from: data)
        #expect(decoded.id == skill.id)
        #expect(decoded.name == "Docker Cleanup")
        #expect(decoded.description == "Remove all stopped containers")
        #expect(decoded.content == "docker system prune -af")
        #expect(decoded.category == .shell)
        #expect(decoded.tags == ["docker", "cleanup"])
    }

    @Test func categoryDisplayName() {
        #expect(SkillCategory.prompt.displayName == "Prompts")
        #expect(SkillCategory.shell.displayName == "Shell")
        #expect(SkillCategory.code.displayName == "Code")
        #expect(SkillCategory.custom.displayName == "Custom")
    }

    @Test func categoryIcon() {
        #expect(SkillCategory.prompt.icon == "text.bubble")
        #expect(SkillCategory.shell.icon == "terminal")
        #expect(SkillCategory.code.icon == "curlybraces")
        #expect(SkillCategory.custom.icon == "star")
    }

    @Test func defaultInitValues() {
        let skill = Skill(name: "Test", content: "echo hello", category: .prompt)
        #expect(skill.description == "")
        #expect(skill.tags.isEmpty)
    }

    @Test func tagsEncoding() throws {
        let skill = Skill(name: "Multi", content: "test", category: .code, tags: ["a", "b", "c"])
        let data = try JSONEncoder().encode(skill)
        let decoded = try JSONDecoder().decode(Skill.self, from: data)
        #expect(decoded.tags == ["a", "b", "c"])
    }

    @Test func originDefaultsToManual() {
        let skill = Skill(name: "Test", content: "echo hello", category: .prompt)
        #expect(skill.origin == .manual)
    }

    @Test func originRoundTrip() throws {
        let skill = Skill(name: "Claude", content: "test", category: .shell, origin: .claude)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Skill.self, from: data)
        #expect(decoded.origin == .claude)
    }

    @Test func backwardCompatWithoutOrigin() throws {
        // Simulate JSON from before origin field existed
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "description": "Old skill",
            "content": "echo hi",
            "category": "shell",
            "tags": [],
            "createdAt": "2025-01-01T00:00:00Z",
            "updatedAt": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Skill.self, from: json)
        #expect(decoded.origin == .manual)
        #expect(decoded.name == "Legacy")
    }
}
