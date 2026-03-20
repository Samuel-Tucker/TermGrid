import Foundation

@MainActor @Observable
final class SkillsManager {
    private(set) var skills: [Skill] = []
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        loadSkills()
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TermGrid").appendingPathComponent("skills")
    }

    // MARK: - CRUD

    func addSkill(_ skill: Skill) {
        skills.append(skill)
        save()
    }

    func updateSkill(_ skill: Skill) {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        skills[index] = skill
        save()
    }

    func removeSkill(id: UUID) {
        skills.removeAll { $0.id == id }
        save()
    }

    func importOrUpdate(_ incoming: [Skill]) {
        for skill in incoming {
            if let idx = skills.firstIndex(where: { $0.name.lowercased().trimmingCharacters(in: .whitespaces) == skill.name.lowercased().trimmingCharacters(in: .whitespaces) }) {
                var updated = skill
                updated.id = skills[idx].id
                updated.createdAt = skills[idx].createdAt
                skills[idx] = updated
            } else {
                skills.append(skill)
            }
        }
        save()
    }

    // MARK: - Filtering

    func filtered(by category: SkillCategory?, query: String) -> [Skill] {
        var result = skills
        if let category {
            result = result.filter { $0.category == category }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            result = result.filter { skill in
                skill.name.lowercased().contains(q) ||
                skill.description.lowercased().contains(q) ||
                skill.content.lowercased().contains(q) ||
                skill.tags.contains { $0.lowercased().contains(q) }
            }
        }
        return result
    }

    // MARK: - Persistence

    private static let fileName = "skills.json"

    private func save() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(skills) else { return }
        try? data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    private func loadSkills() {
        let fileURL = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let loaded = try? decoder.decode([Skill].self, from: data) else {
            print("[TermGrid] Failed to decode skills.json — starting with empty list")
            return
        }
        skills = loaded
    }
}
