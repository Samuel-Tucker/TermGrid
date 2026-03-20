@testable import TermGrid
import Testing

@Suite("PersistenceManager Tests")
struct PersistenceManagerTests {

    @Test func saveAndLoad() throws {
        let dir = try PersistenceTestHelpers.makeTempDir()
        defer { PersistenceTestHelpers.removeTempDir(dir) }
        let manager = PersistenceManager(directory: dir)
        let workspace = Workspace(gridLayout: .three_by_two)
        try manager.save(workspace)
        let loaded = try manager.load()
        #expect(loaded?.gridLayout == .three_by_two)
        #expect(loaded?.cells.count == 6)
    }

    @Test func loadReturnsNilWhenNoFile() throws {
        let dir = try PersistenceTestHelpers.makeTempDir()
        defer { PersistenceTestHelpers.removeTempDir(dir) }
        let manager = PersistenceManager(directory: dir)
        let result = try manager.load()
        #expect(result == nil)
    }

    @Test func corruptFileIsRenamedAndReturnsNil() throws {
        let dir = try PersistenceTestHelpers.makeTempDir()
        defer { PersistenceTestHelpers.removeTempDir(dir) }
        let manager = PersistenceManager(directory: dir)
        try PersistenceTestHelpers.writeCorruptFile(in: dir)
        let result = try manager.load()
        #expect(result == nil)
        #expect(PersistenceTestHelpers.fileExists(at: dir, named: "workspace.json.corrupt"))
    }

    @Test func createsDirectoryIfNeeded() throws {
        let dir = try PersistenceTestHelpers.makeTempDir()
        defer { PersistenceTestHelpers.removeTempDir(dir) }
        let nestedDir = PersistenceTestHelpers.nestedDir(under: dir, path: "sub/dir")
        let nestedManager = PersistenceManager(directory: nestedDir)
        let workspace = Workspace()
        try nestedManager.save(workspace)
        let loaded = try nestedManager.load()
        #expect(loaded != nil)
    }

    // MARK: - Collection Format

    @Test func saveAndLoadCollection() throws {
        let dir = try PersistenceTestHelpers.makeTempDir()
        defer { PersistenceTestHelpers.removeTempDir(dir) }
        let manager = PersistenceManager(directory: dir)
        let ws1 = Workspace(name: "First", gridLayout: .two_by_two)
        let ws2 = Workspace(name: "Second", gridLayout: .three_by_two)
        let data = WorkspaceCollectionData(activeWorkspaceIndex: 1, workspaces: [ws1, ws2])
        try manager.saveCollection(data)
        let loaded = try manager.loadCollection()
        #expect(loaded?.workspaces.count == 2)
        #expect(loaded?.activeWorkspaceIndex == 1)
        #expect(loaded?.workspaces[0].name == "First")
        #expect(loaded?.workspaces[1].name == "Second")
    }

    @Test func loadCollectionReturnsNilWhenNoFile() throws {
        let dir = try PersistenceTestHelpers.makeTempDir()
        defer { PersistenceTestHelpers.removeTempDir(dir) }
        let manager = PersistenceManager(directory: dir)
        let result = try manager.loadCollection()
        #expect(result == nil)
    }

    @Test func corruptCollectionFileIsRenamedAndReturnsNil() throws {
        let dir = try PersistenceTestHelpers.makeTempDir()
        defer { PersistenceTestHelpers.removeTempDir(dir) }
        let manager = PersistenceManager(directory: dir)
        // Write corrupt file
        try PersistenceTestHelpers.writeCorruptFile(in: dir, named: "workspaces.json")
        let result = try manager.loadCollection()
        #expect(result == nil)
        #expect(PersistenceTestHelpers.fileExists(at: dir, named: "workspaces.json.corrupt"))
    }
}
