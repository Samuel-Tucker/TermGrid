@testable import TermGrid
import Testing
import Foundation

@Suite("InMemoryTrie Tests")
struct InMemoryTrieTests {

    @Test func insertAndSearch() {
        let trie = InMemoryTrie()
        let ts = Date().timeIntervalSince1970
        trie.insert(prefix: "gi", completion: "git", frequency: 5, lastUsed: ts, domain: "shell")
        trie.insert(prefix: "gi", completion: "gist", frequency: 2, lastUsed: ts, domain: "shell")

        let results = trie.search(prefix: "gi", domain: "shell")
        #expect(results.count == 2)
        #expect(results[0].completion == "git") // higher frequency
    }

    @Test func loadFromRecords() {
        let trie = InMemoryTrie()
        let ts = Date().timeIntervalSince1970
        let records = [
            PrefixRecord(prefix: "co", completion: "commit", frequency: 10, lastUsed: ts, domain: "shell"),
            PrefixRecord(prefix: "co", completion: "command", frequency: 3, lastUsed: ts, domain: "shell"),
        ]
        trie.load(from: records)
        let results = trie.search(prefix: "co", domain: "shell")
        #expect(results.count == 2)
        #expect(results[0].completion == "commit")
    }

    @Test func searchLimit() {
        let trie = InMemoryTrie()
        let ts = Date().timeIntervalSince1970
        for i in 0..<20 {
            trie.insert(prefix: "t", completion: "token\(i)", frequency: 1, lastUsed: ts, domain: "shell")
        }
        let results = trie.search(prefix: "t", domain: "shell", limit: 5)
        #expect(results.count == 5)
    }

    @Test func caseInsensitiveSearch() {
        let trie = InMemoryTrie()
        let ts = Date().timeIntervalSince1970
        trie.insert(prefix: "GI", completion: "git", frequency: 5, lastUsed: ts, domain: "shell")

        let results = trie.search(prefix: "gi", domain: "shell")
        #expect(results.count == 1)
    }

    @Test func entryCount() {
        let trie = InMemoryTrie()
        let ts = Date().timeIntervalSince1970
        trie.insert(prefix: "gi", completion: "git", frequency: 1, lastUsed: ts, domain: "shell")
        trie.insert(prefix: "gi", completion: "gist", frequency: 1, lastUsed: ts, domain: "shell")
        #expect(trie.entryCount == 2)
    }

    @Test func duplicateInsertUpdatesFrequency() {
        let trie = InMemoryTrie()
        let ts = Date().timeIntervalSince1970
        trie.insert(prefix: "gi", completion: "git", frequency: 3, lastUsed: ts, domain: "shell")
        trie.insert(prefix: "gi", completion: "git", frequency: 2, lastUsed: ts, domain: "shell")
        #expect(trie.entryCount == 1)
        let results = trie.search(prefix: "gi", domain: "shell")
        #expect(results.count == 1)
    }

    @Test func noResultsForUnknownPrefix() {
        let trie = InMemoryTrie()
        let results = trie.search(prefix: "xyz", domain: "shell")
        #expect(results.isEmpty)
    }

    @Test func domainFiltering() {
        let trie = InMemoryTrie()
        let ts = Date().timeIntervalSince1970
        trie.insert(prefix: "he", completion: "hello", frequency: 5, lastUsed: ts, domain: "shell")
        trie.insert(prefix: "he", completion: "help", frequency: 3, lastUsed: ts, domain: "prompt")

        let shell = trie.search(prefix: "he", domain: "shell")
        #expect(shell.count == 1)
        #expect(shell[0].completion == "hello")

        let prompt = trie.search(prefix: "he", domain: "prompt")
        #expect(prompt.count == 1)
        #expect(prompt[0].completion == "help")
    }
}
