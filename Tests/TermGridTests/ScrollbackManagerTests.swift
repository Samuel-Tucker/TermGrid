// Tests/TermGridTests/ScrollbackManagerTests.swift
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

    @Test func saveAndLoadPrimary() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        try mgr.save(cellID: cellID, sessionType: .primary, content: "hello world")
        let loaded = mgr.load(cellID: cellID, sessionType: .primary)
        #expect(loaded == "hello world")
    }

    @Test func saveAndLoadSplit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        try mgr.save(cellID: cellID, sessionType: .split, content: "split content")
        let loaded = mgr.load(cellID: cellID, sessionType: .split)
        #expect(loaded == "split content")
    }

    @Test func loadReturnsNilWhenNoFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let loaded = mgr.load(cellID: UUID(), sessionType: .primary)
        #expect(loaded == nil)
    }

    @Test func cleanupRemovesBothFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        try mgr.save(cellID: cellID, sessionType: .primary, content: "p")
        try mgr.save(cellID: cellID, sessionType: .split, content: "s")
        mgr.cleanup(cellID: cellID)
        #expect(mgr.load(cellID: cellID, sessionType: .primary) == nil)
        #expect(mgr.load(cellID: cellID, sessionType: .split) == nil)
    }

    @Test func cleanupAllRemovesOrphans() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let keep = UUID()
        let orphan = UUID()
        try mgr.save(cellID: keep, sessionType: .primary, content: "keep")
        try mgr.save(cellID: orphan, sessionType: .primary, content: "orphan")
        mgr.cleanupAll(keeping: Set([keep]))
        #expect(mgr.load(cellID: keep, sessionType: .primary) == "keep")
        #expect(mgr.load(cellID: orphan, sessionType: .primary) == nil)
    }

    @Test func saveTruncatesTo5000Lines() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        let longContent = (0..<6000).map { "line \($0)" }.joined(separator: "\n")
        try mgr.save(cellID: cellID, sessionType: .primary, content: longContent)
        let loaded = mgr.load(cellID: cellID, sessionType: .primary)!
        let lines = loaded.components(separatedBy: "\n")
        #expect(lines.count == 5000)
        #expect(lines.last == "line 5999")
    }
}
