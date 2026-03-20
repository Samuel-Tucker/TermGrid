@testable import TermGrid
import Testing
import Foundation

@Suite("TerminalContentExtractor Tests")
struct TerminalContentExtractorTests {

    // MARK: - stripAnsi

    @Test func stripAnsiRemovesCSIColorCodes() {
        let input = "\u{1b}[31mHello\u{1b}[0m World"
        let result = TerminalContentExtractor.stripAnsi(input)
        #expect(result == "Hello World")
    }

    @Test func stripAnsiRemovesOSCTitleSequences() {
        let input = "\u{1b}]0;My Terminal Title\u{07}some text"
        let result = TerminalContentExtractor.stripAnsi(input)
        #expect(result == "some text")
    }

    @Test func stripAnsiPreservesCleanText() {
        let input = "Just plain text with no escapes"
        let result = TerminalContentExtractor.stripAnsi(input)
        #expect(result == input)
    }

    @Test func stripAnsiHandlesEmptyString() {
        let result = TerminalContentExtractor.stripAnsi("")
        #expect(result == "")
    }

    @Test func stripAnsiRemovesSingleCharEscSequences() {
        let input = "\u{1b}MLine after reverse index"
        let result = TerminalContentExtractor.stripAnsi(input)
        #expect(result == "Line after reverse index")
    }

    @Test func stripAnsiRemovesControlCharsButKeepsNewlineAndTab() {
        let input = "hello\tworld\n\u{01}\u{02}end"
        let result = TerminalContentExtractor.stripAnsi(input)
        #expect(result == "hello\tworld\nend")
    }

    // MARK: - findLastPromptIndex

    @Test func findLastPromptDetectsDollarSign() {
        let lines = ["some output", "more output", "$ "]
        let result = TerminalContentExtractor.findLastPromptIndex(in: lines)
        #expect(result == 2)
    }

    @Test func findLastPromptDetectsPercentSign() {
        let lines = ["output line", "% "]
        let result = TerminalContentExtractor.findLastPromptIndex(in: lines)
        #expect(result == 1)
    }

    @Test func findLastPromptDetectsClaudeBoxCorner() {
        let lines = ["some text", "\u{2570} done"]
        let result = TerminalContentExtractor.findLastPromptIndex(in: lines)
        #expect(result == 1)
    }

    @Test func findLastPromptDetectsCodexPrompt() {
        let lines = ["output", "codex> "]
        let result = TerminalContentExtractor.findLastPromptIndex(in: lines)
        #expect(result == 1)
    }

    @Test func findLastPromptDetectsAiderPrompt() {
        let lines = ["output", "aider> "]
        let result = TerminalContentExtractor.findLastPromptIndex(in: lines)
        #expect(result == 1)
    }

    @Test func findLastPromptDetectsUserAtHost() {
        let lines = ["output", "user@machine ~/project$ "]
        let result = TerminalContentExtractor.findLastPromptIndex(in: lines)
        #expect(result == 1)
    }

    @Test func findLastPromptReturnsNilWhenNoPrompt() {
        let lines = ["just output", "more output", "no prompt here"]
        let result = TerminalContentExtractor.findLastPromptIndex(in: lines)
        #expect(result == nil)
    }

    // MARK: - extractLastOutput

    @Test func extractLastOutputReturnsContentAfterLastPrompt() {
        let raw = "old stuff\n$ \ncommand output line 1\nline 2"
        let result = TerminalContentExtractor.extractLastOutput(from: raw)
        #expect(result.text == "command output line 1\nline 2")
        #expect(result.wasTruncated == false)
    }

    @Test func extractLastOutputUsesFallbackWhenNoPrompt() {
        // 210 lines with no prompt
        let lines = (1...210).map { "line \($0)" }
        let raw = lines.joined(separator: "\n")
        let result = TerminalContentExtractor.extractLastOutput(from: raw)
        // Should use last 200 lines as fallback
        #expect(result.text.contains("line 11"))
        #expect(result.text.contains("line 210"))
        #expect(!result.text.contains("line 10\n"))
    }

    @Test func extractLastOutputRespectsMaxLinesAndSetsTruncated() {
        let lines = (1...20).map { "line \($0)" }
        let raw = "$ \n" + lines.joined(separator: "\n")
        let result = TerminalContentExtractor.extractLastOutput(from: raw, maxLines: 5)
        #expect(result.wasTruncated == true)
        #expect(result.lineCount == 5)
    }

    @Test func extractLastOutputHandlesEmptyInput() {
        let result = TerminalContentExtractor.extractLastOutput(from: "")
        #expect(result.text == "")
        #expect(result.lineCount == 0)
        #expect(result.wasTruncated == false)
    }

    @Test func extractLastOutputStripsAnsiBeforeProcessing() {
        let raw = "\u{1b}[32m$ \u{1b}[0m\n\u{1b}[31mcolored output\u{1b}[0m"
        let result = TerminalContentExtractor.extractLastOutput(from: raw)
        #expect(result.text == "colored output")
    }
}
