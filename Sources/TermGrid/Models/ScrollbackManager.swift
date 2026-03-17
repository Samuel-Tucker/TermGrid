// Sources/TermGrid/Models/ScrollbackManager.swift
import Foundation

@MainActor
final class ScrollbackManager {
    private let directory: URL
    static let maxLines = 5000

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

    func save(cellID: UUID, sessionType: SessionType, content: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var lines = content.components(separatedBy: "\n")
        if lines.count > Self.maxLines {
            lines = Array(lines.suffix(Self.maxLines))
        }
        let truncated = lines.joined(separator: "\n")
        let url = fileURL(cellID: cellID, sessionType: sessionType)
        try truncated.write(to: url, atomically: true, encoding: .utf8)
    }

    func load(cellID: UUID, sessionType: SessionType) -> String? {
        let url = fileURL(cellID: cellID, sessionType: sessionType)
        return try? String(contentsOf: url, encoding: .utf8)
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
            // Files: {UUID}-primary.txt or {UUID}-split.txt
            // UUID format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
            // Find last hyphen that separates UUID from type suffix
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
        return directory.appendingPathComponent("\(cellID.uuidString)-\(suffix).txt")
    }
}
