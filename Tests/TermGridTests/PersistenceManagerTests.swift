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
}
