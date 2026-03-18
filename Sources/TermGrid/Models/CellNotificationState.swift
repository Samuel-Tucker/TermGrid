import Foundation
import Observation

@MainActor
@Observable
final class CellNotificationState {
    var severity: NotificationSeverity? = nil
    var matchedPattern: String = ""
    var timestamp: Date? = nil
    var showBorderPulse: Bool = false

    /// Agent work shutter — true when an agent is busy working
    var agentBusy: Bool = false
    /// Which agent is working (for display)
    var agentName: String = ""

    func trigger(severity: NotificationSeverity, pattern: String) {
        self.severity = severity
        self.matchedPattern = pattern
        self.timestamp = Date()
        showBorderPulse = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            showBorderPulse = false
        }
    }

    func agentStarted(name: String) {
        agentBusy = true
        agentName = name
    }

    func agentFinished() {
        agentBusy = false
        agentName = ""
    }

    func clear() {
        severity = nil
        matchedPattern = ""
        timestamp = nil
        showBorderPulse = false
    }
}
