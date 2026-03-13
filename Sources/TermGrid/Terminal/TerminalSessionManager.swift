import Foundation
import Observation

@MainActor
@Observable
final class TerminalSessionManager {
    private var sessions: [UUID: TerminalSession] = [:]

    func session(for cellID: UUID) -> TerminalSession? {
        sessions[cellID]
    }

    @discardableResult
    func createSession(for cellID: UUID, workingDirectory: String) -> TerminalSession {
        if let existing = sessions[cellID] {
            existing.kill()
        }
        let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory)
        sessions[cellID] = session
        return session
    }

    func killSession(for cellID: UUID) {
        sessions[cellID]?.kill()
        sessions.removeValue(forKey: cellID)
    }

    func killAll() {
        for session in sessions.values {
            session.kill()
        }
        sessions.removeAll()
    }
}
