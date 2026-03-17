import Foundation
@testable import TermGrid

enum PersistenceTestHelpers {
    static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func removeTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    static func writeCorruptFile(in dir: URL, named name: String = "workspace.json") throws {
        let filePath = dir.appendingPathComponent(name)
        try "not json".write(to: filePath, atomically: true, encoding: .utf8)
    }

    static func fileExists(at dir: URL, named name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    static func nestedDir(under dir: URL, path: String) -> URL {
        dir.appendingPathComponent(path)
    }
}
