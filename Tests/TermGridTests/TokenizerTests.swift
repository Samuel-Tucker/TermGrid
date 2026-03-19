@testable import TermGrid
import Testing

@Suite("Tokenizer Tests")
struct TokenizerTests {

    @Test func whitespaceSplt() {
        let tokens = Tokenizer.tokenize("git commit -m")
        #expect(tokens == ["git", "commit", "-m"])
    }

    @Test func quotedStrings() {
        let tokens = Tokenizer.tokenize(#"git commit -m "hello world""#)
        #expect(tokens == ["git", "commit", "-m", #""hello world""#])
    }

    @Test func singleQuotes() {
        let tokens = Tokenizer.tokenize("echo 'hello world'")
        #expect(tokens == ["echo", "'hello world'"])
    }

    @Test func unbalancedQuotes() {
        let tokens = Tokenizer.tokenize(#"echo "hello"#)
        #expect(tokens == ["echo", #""hello"#])
    }

    @Test func emptyInput() {
        let tokens = Tokenizer.tokenize("")
        #expect(tokens.isEmpty)
    }

    @Test func multipleSpaces() {
        let tokens = Tokenizer.tokenize("git   status")
        #expect(tokens == ["git", "status"])
    }

    @Test func extractPartialMidWord() {
        let (context, partial) = Tokenizer.extractPartial("git comm")
        #expect(context == "git")
        #expect(partial == "comm")
    }

    @Test func extractPartialAfterSpace() {
        let (context, partial) = Tokenizer.extractPartial("git ")
        #expect(context == "git")
        #expect(partial == "")
    }

    @Test func extractPartialSingleWord() {
        let (context, partial) = Tokenizer.extractPartial("gi")
        #expect(context == "")
        #expect(partial == "gi")
    }

    @Test func extractPartialEmpty() {
        let (context, partial) = Tokenizer.extractPartial("")
        #expect(context == "")
        #expect(partial == "")
    }

    @Test func lastNTokens() {
        let tokens = Tokenizer.lastNTokens("git commit -m hello", n: 2)
        #expect(tokens == ["-m", "hello"])
    }

    @Test func lastNTokensFewerThanN() {
        let tokens = Tokenizer.lastNTokens("git", n: 3)
        #expect(tokens == ["git"])
    }
}
