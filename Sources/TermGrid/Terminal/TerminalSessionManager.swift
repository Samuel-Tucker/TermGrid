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
    var floatingSession: TerminalSession? = nil
    var notificationStates: [UUID: CellNotificationState] = [:]

    func notificationState(for cellID: UUID) -> CellNotificationState {
        if let existing = notificationStates[cellID] {
            return existing
        }
        let state = CellNotificationState()
        notificationStates[cellID] = state
        return state
    }

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
        let notifState = notificationState(for: cellID)
        session.onNotification = { match in
            notifState.trigger(severity: match.severity, pattern: match.pattern)
        }
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
        let notifState = notificationState(for: cellID)
        session.onNotification = { match in
            notifState.trigger(severity: match.severity, pattern: match.pattern)
        }
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

    /// Promote the split session to primary: kill the current primary,
    /// move the split session into the primary slot, and clear the split.
    func promoteSplitToPrimary(for cellID: UUID) {
        guard let split = splitSessions[cellID] else { return }
        // Kill the current primary
        sessions[cellID]?.kill()
        // Move split → primary
        sessions[cellID] = split
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

    @discardableResult
    func createFloatingSession() -> TerminalSession {
        floatingSession?.kill()
        let session = TerminalSession(
            cellID: UUID(),
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            sessionType: .primary,
            environment: buildEnvironment()
        )
        floatingSession = session
        return session
    }

    /// Transfer the floating session into a grid cell (without killing it).
    /// Returns true if transfer succeeded.
    @discardableResult
    func adoptFloatingSession(for cellID: UUID) -> Bool {
        guard let session = floatingSession else { return false }
        // Kill any existing session for this cell
        sessions[cellID]?.kill()
        // Move floating session into the grid
        sessions[cellID] = session
        floatingSession = nil
        // Wire notification callback
        let notifState = notificationState(for: cellID)
        session.onNotification = { match in
            notifState.trigger(severity: match.severity, pattern: match.pattern)
        }
        return true
    }

    func killFloatingSession() {
        floatingSession?.kill()
        floatingSession = nil
    }

    func killAll() {
        for session in sessions.values { session.kill() }
        sessions.removeAll()
        for session in splitSessions.values { session.kill() }
        splitSessions.removeAll()
        splitDirections.removeAll()
        floatingSession?.kill()
        floatingSession = nil
    }
}
