import Foundation
import Observation

enum SplitDirection {
    case horizontal  // top / bottom
    case vertical    // left / right
}

@MainActor
@Observable
final class TerminalSessionManager {
    private var sessions: [UUID: TerminalSession] = [:]
    private var splitSessions: [UUID: TerminalSession] = [:]
    private var splitDirections: [UUID: SplitDirection] = [:]
    var vaultKeys: [String: String] = [:]

    func session(for cellID: UUID) -> TerminalSession? {
        sessions[cellID]
    }

    func splitSession(for cellID: UUID) -> TerminalSession? {
        splitSessions[cellID]
    }

    func splitDirection(for cellID: UUID) -> SplitDirection? {
        splitDirections[cellID]
    }

    private func buildEnvironment() -> [String]? {
        guard !vaultKeys.isEmpty else { return nil }
        var env = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        for (key, value) in vaultKeys {
            env.append("\(key)=\(value)")
        }
        return env
    }

    @discardableResult
    func createSession(for cellID: UUID, workingDirectory: String,
                       startImmediately: Bool = true) -> TerminalSession {
        if let existing = sessions[cellID] {
            existing.kill()
        }
        let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory,
                                       sessionType: .primary, environment: buildEnvironment(),
                                       startImmediately: startImmediately)
        sessions[cellID] = session
        return session
    }

    @discardableResult
    func createSplitSession(for cellID: UUID, workingDirectory: String,
                             direction: SplitDirection,
                             startImmediately: Bool = true) -> TerminalSession {
        if let existing = splitSessions[cellID] {
            existing.kill()
        }
        let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory,
                                       sessionType: .split, environment: buildEnvironment(),
                                       startImmediately: startImmediately)
        splitSessions[cellID] = session
        splitDirections[cellID] = direction
        return session
    }

    func changeSplitDirection(for cellID: UUID, to direction: SplitDirection) {
        splitDirections[cellID] = direction
    }

    func killSplitSession(for cellID: UUID) {
        splitSessions[cellID]?.kill()
        splitSessions.removeValue(forKey: cellID)
        splitDirections.removeValue(forKey: cellID)
    }

    func killSession(for cellID: UUID) {
        sessions[cellID]?.kill()
        sessions.removeValue(forKey: cellID)
        splitSessions[cellID]?.kill()
        splitSessions.removeValue(forKey: cellID)
        splitDirections.removeValue(forKey: cellID)
    }

    func killAll() {
        for session in sessions.values { session.kill() }
        sessions.removeAll()
        for session in splitSessions.values { session.kill() }
        splitSessions.removeAll()
        splitDirections.removeAll()
    }
}
