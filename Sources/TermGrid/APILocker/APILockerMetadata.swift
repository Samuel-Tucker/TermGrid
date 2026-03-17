import Foundation

struct APIKeyEntry: Codable, Identifiable {
    let id: UUID
    var name: String
    var envVarName: String
    var brandColor: String
    var docsURL: String?
    var agentNotes: String?
    var createdAt: Date
    var maskedKey: String

    init(id: UUID = UUID(), name: String, envVarName: String, brandColor: String,
         docsURL: String?, agentNotes: String?, maskedKey: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.envVarName = envVarName
        self.brandColor = brandColor
        self.docsURL = docsURL
        self.agentNotes = agentNotes
        self.maskedKey = maskedKey
        self.createdAt = createdAt
    }

    static func suggestEnvVarName(from name: String) -> String {
        let base = name.uppercased().replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return "\(base)_API_KEY"
    }

    private static let brandColors: [(pattern: String, color: String)] = [
        ("openai", "#10A37F"), ("anthropic", "#D4A574"), ("stripe", "#635BFF"),
        ("google", "#4285F4"), ("aws", "#FF9900"), ("azure", "#0078D4"),
        ("github", "#8B5CF6"), ("cloudflare", "#F6821F"),
    ]

    static func suggestBrandColor(for name: String) -> String? {
        let lower = name.lowercased()
        return brandColors.first { lower.contains($0.pattern) }?.color
    }
}

struct APILockerMetadata: Codable {
    var pinHash: String
    var pinSalt: String
    var entries: [APIKeyEntry]
    var isPremium: Bool

    init(pinHash: String, pinSalt: String, entries: [APIKeyEntry] = [], isPremium: Bool = false) {
        self.pinHash = pinHash
        self.pinSalt = pinSalt
        self.entries = entries
        self.isPremium = isPremium
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinHash = try container.decode(String.self, forKey: .pinHash)
        pinSalt = try container.decode(String.self, forKey: .pinSalt)
        entries = try container.decode([APIKeyEntry].self, forKey: .entries)
        isPremium = (try? container.decodeIfPresent(Bool.self, forKey: .isPremium)) ?? false
    }

    func hasEnvVarName(_ name: String) -> Bool {
        entries.contains { $0.envVarName == name }
    }

    private static let fileName = "metadata.json"

    static func save(_ metadata: APILockerMetadata, to directory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    static func load(from directory: URL) throws -> APILockerMetadata? {
        let fileURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(APILockerMetadata.self, from: data)
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TermGrid").appendingPathComponent("api-locker")
    }
}
