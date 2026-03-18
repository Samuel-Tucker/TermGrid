import Foundation
import Observation

@MainActor
@Observable
final class CellNotificationState {
    var severity: NotificationSeverity? = nil
    var matchedPattern: String = ""
    var timestamp: Date? = nil
    var showBorderPulse: Bool = false

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

    func clear() {
        severity = nil
        matchedPattern = ""
        timestamp = nil
        showBorderPulse = false
    }
}
