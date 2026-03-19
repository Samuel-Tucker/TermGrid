@testable import TermGrid
import Testing
import Foundation

@Suite("HistoryImporter Tests")
struct HistoryImporterTests {

    @Test func parseZshFormat() throws {
        let content = """
        : 1710000000:0;git status
        : 1710000100:0;docker run -it ubuntu
        : 1710000200:0;ls -la
        """
        let path = NSTemporaryDirectory() + "test_zsh_history_\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entries = HistoryImporter.parseZshHistory(at: path)
        #expect(entries.count == 3)
        #expect(entries[0].command == "git status")
        #expect(entries[1].command == "docker run -it ubuntu")
        #expect(entries[2].command == "ls -la")
    }

    @Test func parseZshTimestamp() throws {
        let content = ": 1710000000:0;echo hello\n"
        let path = NSTemporaryDirectory() + "test_zsh_ts_\(UUID().uuidString)"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entries = HistoryImporter.parseZshHistory(at: path)
        #expect(entries.count == 1)
        #expect(entries[0].timestamp.timeIntervalSince1970 == 1710000000)
    }

    @Test func sanitizeEnvVars() {
        let result = HistoryImporter.sanitize("export API_KEY=sk-1234567890")
        #expect(!result.contains("sk-1234567890"))
    }

    @Test func sanitizeGitHubToken() {
        let result = HistoryImporter.sanitize("curl -H 'Authorization: Bearer ghp_abc123'")
        #expect(!result.contains("ghp_abc123"))
        #expect(result.contains("<REDACTED>"))
    }

    @Test func sanitizeSecretPrefix() {
        let result = HistoryImporter.sanitize("echo sk-abc123def456")
        #expect(!result.contains("sk-abc123def456"))
    }

    @Test func sanitizeMultipleOccurrences() {
        let result = HistoryImporter.sanitize("curl -H 'Bearer token1' -H 'Bearer token2'")
        #expect(!result.contains("token1"))
        #expect(!result.contains("token2"))
    }

    @Test func sanitizeLowercaseEnvVars() {
        let result = HistoryImporter.sanitize("api_key=secret123 db_url=postgres://user:pass@host")
        #expect(!result.contains("secret123"))
        #expect(!result.contains("postgres://"))
    }

    @Test func sanitizePreservesNormalCommands() {
        let result = HistoryImporter.sanitize("git commit -m 'fix tests'")
        #expect(result == "git commit -m 'fix tests'")
    }

    @Test func importPopulatesAllTables() throws {
        let db = try AutocompleteDB(path: ":memory:")
        let engine = TrigramEngine(db: db)
        let trie = InMemoryTrie()

        let entries = [
            HistoryEntry(command: "git status", timestamp: Date()),
            HistoryEntry(command: "git commit -m", timestamp: Date()),
        ]

        let count = try HistoryImporter.importInto(
            db: db, trigramEngine: engine, trie: trie, entries: entries
        )

        #expect(count == 2)

        // Corpus populated
        let corpus = try db.recentCorpus(limit: 10)
        #expect(corpus.count == 2)

        // Trigrams populated
        let trigrams = try db.allTrigrams()
        #expect(!trigrams.isEmpty)

        // Prefixes populated
        let prefixes = try db.allPrefixes()
        #expect(!prefixes.isEmpty)

        // Trie populated
        #expect(trie.entryCount > 0)
    }

    @Test func emptyHistoryImportsZero() throws {
        let db = try AutocompleteDB(path: ":memory:")
        let engine = TrigramEngine(db: db)
        let trie = InMemoryTrie()

        let count = try HistoryImporter.importInto(
            db: db, trigramEngine: engine, trie: trie, entries: []
        )
        #expect(count == 0)
    }
}
