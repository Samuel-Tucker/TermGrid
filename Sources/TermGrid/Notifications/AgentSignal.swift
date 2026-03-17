import Foundation

struct SocketPayload: Codable {
    let cellID: String
    let sessionType: String
    let agentType: String
    let eventType: String
    let message: String
}

struct AgentSignal {
    let cellID: UUID
    let sessionType: SessionType
    let agentType: AgentType
    let eventType: EventType
    let fullMessage: String
    let summary: String

    init?(from payload: SocketPayload) {
        guard let cellID = UUID(uuidString: payload.cellID),
              let sessionType = SessionType(rawValue: payload.sessionType),
              let agentType = AgentType(rawValue: payload.agentType),
              let eventType = EventType(rawValue: payload.eventType) else {
            return nil
        }
        self.cellID = cellID
        self.sessionType = sessionType
        self.agentType = agentType
        self.eventType = eventType
        self.fullMessage = payload.message
        self.summary = MessageParser.extractSummary(from: payload.message)
    }
}

enum SessionType: String, Codable {
    case primary, split
}

enum AgentType: String, Codable {
    case claudeCode, codex
}

enum EventType: String, Codable {
    case complete, needsInput
}
