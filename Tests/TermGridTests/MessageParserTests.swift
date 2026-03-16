@testable import TermGrid
import Testing

@Suite("MessageParser Tests")
struct MessageParserTests {

    @Test func extractsQuestionFromEnd() {
        let message = "I've refactored the module. All tests pass. Shall I continue to the next task?"
        let summary = MessageParser.extractSummary(from: message)
        #expect(summary == "Shall I continue to the next task?")
    }

    @Test func extractsQuestionFromMultipleSentences() {
        let message = "Done. Do you want me to proceed?"
        let summary = MessageParser.extractSummary(from: message)
        #expect(summary == "Do you want me to proceed?")
    }

    @Test func fallsBackToLastSentenceWhenNoQuestion() {
        let message = "I've completed the refactoring. All 30 tests pass."
        let summary = MessageParser.extractSummary(from: message)
        #expect(summary == "All 30 tests pass.")
    }

    @Test func handlesMultiParagraphMessage() {
        let message = """
        I made the following changes:
        - Updated the config
        - Fixed the bug

        Everything looks good. Should I deploy?
        """
        let summary = MessageParser.extractSummary(from: message)
        #expect(summary == "Should I deploy?")
    }

    @Test func handlesSingleWordMessage() {
        let summary = MessageParser.extractSummary(from: "Done")
        #expect(summary == "Done")
    }

    @Test func handlesEmptyMessage() {
        let summary = MessageParser.extractSummary(from: "")
        #expect(summary == "")
    }

    @Test func handlesSingleSentenceQuestion() {
        let summary = MessageParser.extractSummary(from: "What should I do next?")
        #expect(summary == "What should I do next?")
    }

    @Test func handlesMessageWithOnlyWhitespace() {
        let summary = MessageParser.extractSummary(from: "   \n\n  ")
        #expect(summary == "")
    }

    @Test func extractsLastQuestionWhenMultipleQuestions() {
        let message = "Should I fix the tests? Or should I move on to the next feature?"
        let summary = MessageParser.extractSummary(from: message)
        #expect(summary == "Or should I move on to the next feature?")
    }
}
