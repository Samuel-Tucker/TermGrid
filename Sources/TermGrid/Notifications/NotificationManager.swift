import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let sessionManager: TerminalSessionManager
    private let collection: WorkspaceCollection

    static let categoryIdentifier = "AGENT_MESSAGE"
    static let replyActionIdentifier = "REPLY_ACTION"
    static let dismissActionIdentifier = "DISMISS_ACTION"

    init(sessionManager: TerminalSessionManager, collection: WorkspaceCollection) {
        self.sessionManager = sessionManager
        self.collection = collection
        super.init()
    }

    func setup() {
        // UNUserNotificationCenter requires a proper app bundle — skip when running via `swift run`
        guard Bundle.main.bundleIdentifier != nil else {
            print("[TermGrid] No bundle identifier — notifications disabled (use .app bundle)")
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { print("[TermGrid] Notification permission error: \(error)") }
        }

        let replyAction = UNTextInputNotificationAction(
            identifier: Self.replyActionIdentifier,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your response..."
        )
        let dismissAction = UNNotificationAction(
            identifier: Self.dismissActionIdentifier,
            title: "Dismiss",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [replyAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func postNotification(for signal: AgentSignal) {
        // Update agent shutter state
        let notifState = sessionManager.notificationState(for: signal.cellID)
        switch signal.eventType {
        case .started:
            notifState.agentStarted(name: signal.agentType.displayName)
            // Set detected agent on the session for badge display
            let session: TerminalSession? = switch signal.sessionType {
            case .primary: sessionManager.session(for: signal.cellID)
            case .split: sessionManager.splitSession(for: signal.cellID)
            }
            session?.detectedAgent = signal.agentType
            return // don't post a macOS notification for "started"
        case .complete:
            notifState.agentFinished()
        case .needsInput:
            notifState.agentFinished() // agent needs user — unshutter
        }

        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()

        let allCells = collection.workspaces.flatMap(\.cells)
        if let cell = allCells.first(where: { $0.id == signal.cellID }) {
            content.title = cell.label.isEmpty ? "TermGrid" : cell.label
            let termLabel = signal.sessionType == .primary ? cell.terminalLabel : cell.splitTerminalLabel
            if !termLabel.isEmpty {
                content.subtitle = termLabel
            }
        } else {
            content.title = "TermGrid"
        }

        if signal.summary != signal.fullMessage && !signal.summary.isEmpty {
            content.body = signal.summary + "\n\n" + signal.fullMessage
        } else {
            content.body = signal.fullMessage
        }

        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "cellID": signal.cellID.uuidString,
            "sessionType": signal.sessionType.rawValue
        ]
        content.threadIdentifier = signal.cellID.uuidString
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard response.actionIdentifier == "REPLY_ACTION",
              let textResponse = response as? UNTextInputNotificationResponse,
              let cellIDString = userInfo["cellID"] as? String,
              let cellID = UUID(uuidString: cellIDString),
              let sessionTypeString = userInfo["sessionType"] as? String,
              let sessionType = SessionType(rawValue: sessionTypeString) else {
            completionHandler()
            return
        }

        let replyText = textResponse.userText

        Task { @MainActor in
            let session: TerminalSession? = switch sessionType {
            case .primary: sessionManager.session(for: cellID)
            case .split: sessionManager.splitSession(for: cellID)
            }

            if let session, session.isRunning {
                session.send(replyText + "\r")
            } else {
                let content = UNMutableNotificationContent()
                content.title = "TermGrid"
                content.body = "Session no longer active — reply could not be delivered."
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                try? await center.add(request)
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
