import Foundation

/// On-disk format for workspace collection (schema version 2).
struct WorkspaceCollectionData: Codable {
    var schemaVersion: Int = 2
    var activeWorkspaceIndex: Int
    var workspaces: [Workspace]
}

final class PersistenceManager {
    let directory: URL
    private let fileName = "workspace.json"
    private let collectionFileName = "workspaces.json"

    private var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    private var corruptURL: URL {
        directory.appendingPathComponent("\(fileName).corrupt")
    }

    private var collectionFileURL: URL {
        directory.appendingPathComponent(collectionFileName)
    }

    private var collectionCorruptURL: URL {
        directory.appendingPathComponent("\(collectionFileName).corrupt")
    }

    /// Production initializer: uses Application Support/TermGrid/
    convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.init(directory: appSupport.appendingPathComponent("TermGrid"))
    }

    /// Testable initializer: uses any directory
    init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Single Workspace (legacy)

    func load() throws -> Workspace? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode(Workspace.self, from: data)
        } catch {
            print("[TermGrid] Warning: workspace.json is corrupted — renaming to .corrupt")
            if fm.fileExists(atPath: corruptURL.path) {
                try? fm.removeItem(at: corruptURL)
            }
            try? fm.moveItem(at: fileURL, to: corruptURL)
            return nil
        }
    }

    func save(_ workspace: Workspace) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(workspace)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Collection (schema v2)

    func loadCollection() throws -> WorkspaceCollectionData? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: collectionFileURL.path) else { return nil }

        let data = try Data(contentsOf: collectionFileURL)
        do {
            return try JSONDecoder().decode(WorkspaceCollectionData.self, from: data)
        } catch {
            print("[TermGrid] Warning: workspaces.json is corrupted — renaming to .corrupt")
            if fm.fileExists(atPath: collectionCorruptURL.path) {
                try? fm.removeItem(at: collectionCorruptURL)
            }
            try? fm.moveItem(at: collectionFileURL, to: collectionCorruptURL)
            return nil
        }
    }

    func saveCollection(_ collection: WorkspaceCollectionData) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(collection)
        try data.write(to: collectionFileURL, options: .atomic)
    }
}
