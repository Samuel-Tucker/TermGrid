import Foundation

enum SkillCategory: String, Codable, CaseIterable {
    case prompt, shell, code, custom

    var displayName: String {
        switch self {
        case .prompt: return "Prompts"
        case .shell:  return "Shell"
        case .code:   return "Code"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .prompt: return "text.bubble"
        case .shell:  return "terminal"
        case .code:   return "curlybraces"
        case .custom: return "star"
        }
    }
}

enum SkillOrigin: String, Codable {
    case manual, claude, codex
}

struct Skill: Identifiable {
    var id: UUID
    var name: String
    var description: String
    var content: String
    var category: SkillCategory
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var origin: SkillOrigin

    init(id: UUID = UUID(), name: String, description: String = "", content: String,
         category: SkillCategory, tags: [String] = [], createdAt: Date = Date(),
         updatedAt: Date = Date(), origin: SkillOrigin = .manual) {
        self.id = id
        self.name = name
        self.description = description
        self.content = content
        self.category = category
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.origin = origin
    }
}

extension Skill: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, description, content, category, tags, createdAt, updatedAt, origin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        content = try c.decode(String.self, forKey: .content)
        category = try c.decode(SkillCategory.self, forKey: .category)
        tags = try c.decode([String].self, forKey: .tags)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        origin = try c.decodeIfPresent(SkillOrigin.self, forKey: .origin) ?? .manual
    }
}
