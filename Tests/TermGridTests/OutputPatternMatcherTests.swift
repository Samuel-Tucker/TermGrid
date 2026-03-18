@testable import TermGrid
import Testing
import Foundation

@Suite("OutputPatternMatcher Tests")
struct OutputPatternMatcherTests {

    @Test func matchesBuildComplete() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("Build complete!\n".utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .success)
    }

    @Test func matchesTestPassed() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("✔ Test run with 42 tests in 5 suites passed after 0.3 seconds.\n".utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .success)
    }

    @Test func matchesErrorAtLineStart() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("error: cannot find module\n".utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .error)
    }

    @Test func doesNotMatchErrorMidLine() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("some text error: not at start\n".utf8))
        #expect(matches.isEmpty)
    }

    @Test func matchesFailAtLineStart() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("FAIL some test\n".utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .error)
    }

    @Test func noMatchOnNormalOutput() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("sam@Mac ~ % ls\nfile1.txt\nfile2.txt\n".utf8))
        #expect(matches.isEmpty)
    }

    @Test func handlesChunkBoundaries() {
        var matcher = OutputPatternMatcher()
        let matches1 = matcher.processChunk(Array("Build comp".utf8))
        #expect(matches1.isEmpty)
        let matches2 = matcher.processChunk(Array("lete!\n".utf8))
        #expect(matches2.count == 1)
        #expect(matches2[0].severity == .success)
    }

    @Test func stripsAnsiEscapes() {
        var matcher = OutputPatternMatcher()
        let ansi = "\u{1b}[31merror:\u{1b}[0m something broke\n"
        let matches = matcher.processChunk(Array(ansi.utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .error)
    }

    @Test func multipleMatchesInOneChunk() {
        var matcher = OutputPatternMatcher()
        let chunk = "Build complete!\nerror: but then this\n"
        let matches = matcher.processChunk(Array(chunk.utf8))
        #expect(matches.count == 2)
    }
}
