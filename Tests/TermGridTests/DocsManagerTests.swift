@testable import TermGrid
import Foundation
import Testing

@Suite("DocsManager Tests")
@MainActor
struct DocsManagerTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermGridDocsTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func addDocCreatesEntry() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let keyID = UUID()
        let entry = manager.addDoc(url: "https://api.openai.com/docs", forKey: keyID)
        #expect(entry != nil)
        #expect(entry?.sourceURL == "https://api.openai.com/docs")
        #expect(entry?.keyEntryID == keyID)
        #expect(entry?.status == .pending)
        #expect(manager.totalDocCount == 1)
    }

    @Test func addDocRejectsInvalidURL() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        #expect(manager.addDoc(url: "javascript:alert(1)", forKey: UUID()) == nil)
    }

    @Test func addDocRejectsFileURL() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        #expect(manager.addDoc(url: "file:///etc/passwd", forKey: UUID()) == nil)
    }

    @Test func addDocEnforces10Limit() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let keyID = UUID()
        for i in 0..<10 {
            #expect(manager.addDoc(url: "https://example.com/doc\(i)", forKey: keyID) != nil)
        }
        #expect(manager.addDoc(url: "https://example.com/doc10", forKey: keyID) == nil)
        #expect(manager.docsForKey(keyID).count == 10)
    }

    @Test func removeDocDeletesEntryAndFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let entry = manager.addDoc(url: "https://example.com", forKey: UUID())!
        let filePath = dir.appendingPathComponent("\(entry.id.uuidString).md")
        try "# Test".write(to: filePath, atomically: true, encoding: .utf8)
        manager.removeDoc(entry)
        #expect(manager.totalDocCount == 0)
        #expect(!FileManager.default.fileExists(atPath: filePath.path))
    }

    @Test func removeDocsForKeyCascadeDeletes() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let keyID = UUID()
        _ = manager.addDoc(url: "https://example.com/a", forKey: keyID)
        _ = manager.addDoc(url: "https://example.com/b", forKey: keyID)
        #expect(manager.docsForKey(keyID).count == 2)
        manager.removeDocsForKey(keyID)
        #expect(manager.docsForKey(keyID).count == 0)
    }

    @Test func docsForKeyFiltersCorrectly() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let key1 = UUID(), key2 = UUID()
        _ = manager.addDoc(url: "https://example.com/a", forKey: key1)
        _ = manager.addDoc(url: "https://example.com/b", forKey: key2)
        #expect(manager.docsForKey(key1).count == 1)
        #expect(manager.docsForKey(key2).count == 1)
    }

    @Test func persistenceRoundTrip() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager1 = DocsManager(directory: dir)
        let keyID = UUID()
        _ = manager1.addDoc(url: "https://example.com/doc", forKey: keyID)
        let manager2 = DocsManager(directory: dir)
        #expect(manager2.totalDocCount == 1)
        #expect(manager2.docsForKey(keyID).first?.sourceURL == "https://example.com/doc")
    }

    @Test func loadContentReturnsNilWhenNoFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let entry = manager.addDoc(url: "https://example.com", forKey: UUID())!
        #expect(manager.loadContent(for: entry) == nil)
    }

    @Test func loadContentReturnsFileContents() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let entry = manager.addDoc(url: "https://example.com", forKey: UUID())!
        let filePath = dir.appendingPathComponent("\(entry.id.uuidString).md")
        try "# Hello World".write(to: filePath, atomically: true, encoding: .utf8)
        #expect(manager.loadContent(for: entry) == "# Hello World")
    }

    @Test func titleExtractionFromMarkdown() {
        #expect(DocsManager.extractTitle(from: "# My API Docs\nSome content") == "My API Docs")
        #expect(DocsManager.extractTitle(from: "No heading here") == nil)
        #expect(DocsManager.extractTitle(from: "## Secondary Heading\nContent") == "Secondary Heading")
    }

    @Test func urlValidation() {
        #expect(DocsManager.isValidDocURL("https://api.openai.com/docs") == true)
        #expect(DocsManager.isValidDocURL("http://example.com") == true)
        #expect(DocsManager.isValidDocURL("file:///etc/passwd") == false)
        #expect(DocsManager.isValidDocURL("javascript:alert(1)") == false)
        #expect(DocsManager.isValidDocURL("not a url") == false)
        #expect(DocsManager.isValidDocURL("") == false)
    }
}
