import Foundation
import Observation

enum DocStatus: String, Codable {
    case pending
    case fetched
    case error
}

struct DocEntry: Codable, Identifiable {
    let id: UUID
    let keyEntryID: UUID
    var sourceURL: String
    var title: String
    var fetchedAt: Date?
    var status: DocStatus
    var errorMessage: String?

    var fileName: String { "\(id.uuidString).md" }

    init(id: UUID = UUID(), keyEntryID: UUID, sourceURL: String,
         title: String = "", status: DocStatus = .pending) {
        self.id = id
        self.keyEntryID = keyEntryID
        self.sourceURL = sourceURL
        self.title = title
        self.status = status
    }
}

struct DocsIndex: Codable {
    var schemaVersion: Int = 1
    var entries: [DocEntry]

    init(entries: [DocEntry] = []) {
        self.entries = entries
    }

    private static let fileName = "docs-index.json"

    static func save(_ index: DocsIndex, to directory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    static func load(from directory: URL) -> DocsIndex {
        let fileURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return DocsIndex()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(DocsIndex.self, from: data)) ?? DocsIndex()
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TermGrid").appendingPathComponent("docs")
    }
}

@MainActor
@Observable
final class DocsManager {
    private(set) var index: DocsIndex
    private let directory: URL
    var fetchingIDs: Set<UUID> = []

    init(directory: URL? = nil) {
        let dir = directory ?? DocsIndex.defaultDirectory
        self.directory = dir
        self.index = DocsIndex.load(from: dir)
    }

    var totalDocCount: Int { index.entries.count }

    func docsForKey(_ keyID: UUID) -> [DocEntry] {
        index.entries.filter { $0.keyEntryID == keyID }
    }

    func addDoc(url: String, forKey keyID: UUID) -> DocEntry? {
        guard Self.isValidDocURL(url) else { return nil }
        guard docsForKey(keyID).count < 10 else { return nil }
        let entry = DocEntry(keyEntryID: keyID, sourceURL: url)
        index.entries.append(entry)
        saveIndex()
        return entry
    }

    func removeDoc(_ entry: DocEntry) {
        index.entries.removeAll { $0.id == entry.id }
        let filePath = directory.appendingPathComponent(entry.fileName)
        try? FileManager.default.removeItem(at: filePath)
        saveIndex()
    }

    func removeDocsForKey(_ keyID: UUID) {
        let docs = docsForKey(keyID)
        for doc in docs {
            let filePath = directory.appendingPathComponent(doc.fileName)
            try? FileManager.default.removeItem(at: filePath)
        }
        index.entries.removeAll { $0.keyEntryID == keyID }
        saveIndex()
    }

    func loadContent(for entry: DocEntry) -> String? {
        let filePath = directory.appendingPathComponent(entry.fileName)
        return try? String(contentsOf: filePath, encoding: .utf8)
    }

    func fetchDoc(_ entry: DocEntry, apiKey: String) async {
        guard let idx = index.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        fetchingIDs.insert(entry.id)
        defer { fetchingIDs.remove(entry.id) }

        let encodedURL = entry.sourceURL.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.sourceURL
        guard let requestURL = URL(string: "https://r.jina.ai/\(encodedURL)") else {
            index.entries[idx].status = .error
            index.entries[idx].errorMessage = "Invalid URL"
            saveIndex()
            return
        }

        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        request.setValue("markdown", forHTTPHeaderField: "X-Return-Format")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                index.entries[idx].status = .error
                index.entries[idx].errorMessage = "Invalid or expired API key"
                saveIndex()
                return
            }

            guard httpResponse.statusCode == 200 else {
                index.entries[idx].status = .error
                index.entries[idx].errorMessage = "HTTP \(httpResponse.statusCode)"
                saveIndex()
                return
            }

            var markdown: String
            if data.count > 2_000_000 {
                markdown = String(data: data.prefix(2_000_000), encoding: .utf8) ?? ""
                markdown += "\n\n--- Content truncated (>2 MB) ---"
            } else {
                markdown = String(data: data, encoding: .utf8) ?? ""
            }

            let filePath = directory.appendingPathComponent(entry.fileName)
            try markdown.write(to: filePath, atomically: true, encoding: .utf8)

            index.entries[idx].status = .fetched
            index.entries[idx].fetchedAt = Date()
            index.entries[idx].errorMessage = nil
            if let title = Self.extractTitle(from: markdown) {
                index.entries[idx].title = title
            } else {
                index.entries[idx].title = URL(string: entry.sourceURL)?.lastPathComponent ?? entry.sourceURL
            }
            saveIndex()
        } catch {
            if let idx = index.entries.firstIndex(where: { $0.id == entry.id }) {
                index.entries[idx].status = .error
                index.entries[idx].errorMessage = error.localizedDescription
                saveIndex()
            }
        }
    }

    static func extractTitle(from markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("## ") {
                return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func isValidDocURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host != nil else {
            return false
        }
        return true
    }

    private func saveIndex() {
        try? DocsIndex.save(index, to: directory)
    }
}
