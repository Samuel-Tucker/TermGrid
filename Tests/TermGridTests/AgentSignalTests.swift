@testable import TermGrid
import Testing
import Foundation

@Suite("AgentSignal Tests")
struct AgentSignalTests {

    @Test func decodeValidSocketPayload() throws {
        let json = """
        {"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"primary","agentType":"claudeCode","eventType":"complete","message":"Tests pass. Shall I continue?"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(SocketPayload.self, from: json)
        #expect(payload.cellID == "550e8400-e29b-41d4-a716-446655440000")
        #expect(payload.sessionType == "primary")
        #expect(payload.agentType == "claudeCode")
        #expect(payload.eventType == "complete")
        #expect(payload.message == "Tests pass. Shall I continue?")
    }

    @Test func decodeSocketPayloadWithSplitSession() throws {
        let json = """
        {"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"split","agentType":"codex","eventType":"needsInput","message":"Need approval"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(SocketPayload.self, from: json)
        #expect(payload.sessionType == "split")
        #expect(payload.agentType == "codex")
        #expect(payload.eventType == "needsInput")
    }

    @Test func decodeSocketPayloadMissingFieldThrows() {
        let json = """
        {"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"primary"}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SocketPayload.self, from: json)
        }
    }

    @Test func sessionTypeRawValues() {
        #expect(SessionType.primary.rawValue == "primary")
        #expect(SessionType.split.rawValue == "split")
    }

    @Test func agentTypeRawValues() {
        #expect(AgentType.claudeCode.rawValue == "claudeCode")
        #expect(AgentType.codex.rawValue == "codex")
    }

    @Test func eventTypeRawValues() {
        #expect(EventType.complete.rawValue == "complete")
        #expect(EventType.needsInput.rawValue == "needsInput")
    }

    @Test func socketPayloadToAgentSignal() throws {
        let json = """
        {"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"primary","agentType":"claudeCode","eventType":"complete","message":"All tests pass. Want me to move on?"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(SocketPayload.self, from: json)
        let signal = AgentSignal(from: payload)
        #expect(signal != nil)
        #expect(signal?.cellID == UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000"))
        #expect(signal?.sessionType == .primary)
        #expect(signal?.agentType == .claudeCode)
        #expect(signal?.eventType == .complete)
        #expect(signal?.fullMessage == "All tests pass. Want me to move on?")
        #expect(signal?.summary == "Want me to move on?")
    }

    @Test func socketPayloadWithInvalidUUIDReturnsNil() throws {
        let json = """
        {"cellID":"not-a-uuid","sessionType":"primary","agentType":"claudeCode","eventType":"complete","message":"hello"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(SocketPayload.self, from: json)
        let signal = AgentSignal(from: payload)
        #expect(signal == nil)
    }

    @Test func socketPayloadWithUnknownAgentTypeFallsBackToUnknown() throws {
        let json = """
        {"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"primary","agentType":"cursor","eventType":"complete","message":"done"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(SocketPayload.self, from: json)
        let signal = AgentSignal(from: payload)
        #expect(signal != nil)
        #expect(signal?.agentType == .unknown)
    }

    @Test func agentTypeNewCases() {
        #expect(AgentType.gemini.rawValue == "gemini")
        #expect(AgentType.aider.rawValue == "aider")
        #expect(AgentType.unknown.rawValue == "unknown")
    }

    @Test func socketPayloadWithInvalidSessionTypeReturnsNil() throws {
        let json = """
        {"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"tertiary","agentType":"claudeCode","eventType":"complete","message":"hello"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(SocketPayload.self, from: json)
        let signal = AgentSignal(from: payload)
        #expect(signal == nil)
    }
}
