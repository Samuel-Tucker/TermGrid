import Foundation

@MainActor
final class ScrollbackManager {
    private let directory: URL
    /// Maximum bytes to store per session (1 MB)
    static let maxBytes = 1_000_000

    convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.init(directory: appSupport.appendingPathComponent("TermGrid/scrollback"))
    }

    init(directory: URL) {
        self.directory = directory
    }

    /// Save raw PTY output bytes to disk.
    func saveRaw(cellID: UUID, sessionType: SessionType, data: Data) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Truncate to last maxBytes if needed
        let toSave: Data
        if data.count > Self.maxBytes {
            toSave = data.suffix(Self.maxBytes)
        } else {
            toSave = data
        }
        let url = fileURL(cellID: cellID, sessionType: sessionType)
        try toSave.write(to: url, options: .atomic)
    }

    /// Load raw PTY output bytes from disk.
    func loadRaw(cellID: UUID, sessionType: SessionType) -> Data? {
        let url = fileURL(cellID: cellID, sessionType: sessionType)
        return try? Data(contentsOf: url)
    }

    func cleanup(cellID: UUID) {
        let fm = FileManager.default
        try? fm.removeItem(at: fileURL(cellID: cellID, sessionType: .primary))
        try? fm.removeItem(at: fileURL(cellID: cellID, sessionType: .split))
    }

    func cleanupAll(keeping cellIDs: Set<UUID>) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            let name = url.deletingPathExtension().lastPathComponent
            if let lastHyphen = name.lastIndex(of: "-") {
                let uuidString = String(name[name.startIndex..<lastHyphen])
                if let uuid = UUID(uuidString: uuidString), !cellIDs.contains(uuid) {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    private func fileURL(cellID: UUID, sessionType: SessionType) -> URL {
        let suffix = sessionType == .primary ? "primary" : "split"
        return directory.appendingPathComponent("\(cellID.uuidString)-\(suffix).bin")
    }
}
