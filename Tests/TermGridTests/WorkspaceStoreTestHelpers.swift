import Foundation
@testable import TermGrid

/// Helpers for WorkspaceStore tests.
/// This file imports Foundation (but NOT Testing) to avoid the cross-import overlay issue.
@MainActor
enum WorkspaceStoreTestHelpers {
    struct TestContext: Sendable {
        let dir: URL
        nonisolated func cleanup() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func removeTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    static func makeStore(directory dir: URL) -> WorkspaceStore {
        WorkspaceStore(persistence: PersistenceManager(directory: dir))
    }

    static func makePM(directory dir: URL) -> PersistenceManager {
        PersistenceManager(directory: dir)
    }

    static func saveWorkspace(_ workspace: Workspace, using pm: PersistenceManager) throws {
        try pm.save(workspace)
    }

    static func loadWorkspace(using pm: PersistenceManager) throws -> Workspace? {
        try pm.load()
    }
}
