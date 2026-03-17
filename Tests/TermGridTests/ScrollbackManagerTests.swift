@testable import TermGrid
import Testing
import Foundation

@Suite("ScrollbackManager Tests")
@MainActor
struct ScrollbackManagerTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func saveAndLoadRawPrimary() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        let data = Data("hello world\u{1b}[32m green text \u{1b}[0m".utf8)
        try mgr.saveRaw(cellID: cellID, sessionType: .primary, data: data)
        let loaded = mgr.loadRaw(cellID: cellID, sessionType: .primary)
        #expect(loaded == data)
    }

    @Test func saveAndLoadRawSplit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        let data = Data("split \u{1b}[1mbold\u{1b}[0m".utf8)
        try mgr.saveRaw(cellID: cellID, sessionType: .split, data: data)
        let loaded = mgr.loadRaw(cellID: cellID, sessionType: .split)
        #expect(loaded == data)
    }

    @Test func loadReturnsNilWhenNoFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let loaded = mgr.loadRaw(cellID: UUID(), sessionType: .primary)
        #expect(loaded == nil)
    }

    @Test func cleanupRemovesBothFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        try mgr.saveRaw(cellID: cellID, sessionType: .primary, data: Data([0x41]))
        try mgr.saveRaw(cellID: cellID, sessionType: .split, data: Data([0x42]))
        mgr.cleanup(cellID: cellID)
        #expect(mgr.loadRaw(cellID: cellID, sessionType: .primary) == nil)
        #expect(mgr.loadRaw(cellID: cellID, sessionType: .split) == nil)
    }

    @Test func cleanupAllRemovesOrphans() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let keep = UUID()
        let orphan = UUID()
        try mgr.saveRaw(cellID: keep, sessionType: .primary, data: Data([0x4B]))
        try mgr.saveRaw(cellID: orphan, sessionType: .primary, data: Data([0x4F]))
        mgr.cleanupAll(keeping: Set([keep]))
        #expect(mgr.loadRaw(cellID: keep, sessionType: .primary) != nil)
        #expect(mgr.loadRaw(cellID: orphan, sessionType: .primary) == nil)
    }

    @Test func saveTruncatesLargeData() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        // Create data larger than maxBytes (1 MB)
        let bigData = Data(repeating: 0x41, count: ScrollbackManager.maxBytes + 1000)
        try mgr.saveRaw(cellID: cellID, sessionType: .primary, data: bigData)
        let loaded = mgr.loadRaw(cellID: cellID, sessionType: .primary)!
        #expect(loaded.count == ScrollbackManager.maxBytes)
        // Should keep the LAST maxBytes (suffix)
        #expect(loaded.last == 0x41)
    }

    @Test func preservesEscapeSequences() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        // Raw bytes with ANSI escape sequences, cursor movement, etc.
        let rawBytes: [UInt8] = [
            0x1B, 0x5B, 0x33, 0x32, 0x6D,  // ESC[32m (green)
            0x48, 0x65, 0x6C, 0x6C, 0x6F,  // Hello
            0x1B, 0x5B, 0x30, 0x6D,        // ESC[0m (reset)
            0x0A,                           // newline
            0x1B, 0x5B, 0x48,              // ESC[H (cursor home)
        ]
        let data = Data(rawBytes)
        try mgr.saveRaw(cellID: cellID, sessionType: .primary, data: data)
        let loaded = mgr.loadRaw(cellID: cellID, sessionType: .primary)!
        #expect(loaded == data)
    }
}
