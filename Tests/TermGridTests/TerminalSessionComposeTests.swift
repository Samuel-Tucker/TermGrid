@testable import TermGrid
import Testing

@Suite("TerminalSession Compose Tests")
struct TerminalSessionComposeTests {

    @Test func codexComposeSubmitsInSingleWrite() {
        let writes = TerminalSession.composeWriteChunks(for: "ship the patch", detectedAgent: .codex)
        #expect(writes == ["ship the patch\r"])
    }

    @Test func agentComposePreservesMultilinePrompt() {
        let writes = TerminalSession.composeWriteChunks(
            for: "line one\nline two",
            detectedAgent: .claudeCode
        )
        #expect(writes == ["line one\nline two\r"])
    }

    @Test func shellComposePreservesCommandPerLineExecution() {
        let writes = TerminalSession.composeWriteChunks(
            for: "git status\nswift test",
            detectedAgent: nil
        )
        #expect(writes == ["git status\r", "swift test\r"])
    }

    @Test func unknownAgentFallsBackToShellSemantics() {
        let writes = TerminalSession.composeWriteChunks(
            for: "echo one\necho two",
            detectedAgent: .unknown
        )
        #expect(writes == ["echo one\r", "echo two\r"])
    }
}
