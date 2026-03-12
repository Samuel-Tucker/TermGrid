import Foundation

final class PersistenceManager {
    private let directory: URL
    private let fileName = "workspace.json"

    private var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    private var corruptURL: URL {
        directory.appendingPathComponent("\(fileName).corrupt")
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
}
