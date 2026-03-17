# Inline Notification System Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add iMessage-style inline notifications that let users reply to AI agent events (Claude Code, Codex CLI) directly from the macOS notification banner, routing replies back to the correct terminal PTY.

**Architecture:** New `Notifications/` module with four files: `AgentSignal.swift` (models), `MessageParser.swift` (summary extraction), `SocketServer.swift` (Unix domain socket listener), `NotificationManager.swift` (macOS notification lifecycle + reply routing). Hook scripts in `~/.termgrid/hooks/` bridge agent events to the socket. Two existing files modified: `TerminalSession.swift` (env var injection) and `TermGridApp.swift` (wiring).

**Tech Stack:** Swift, SwiftUI, UserNotifications framework, Darwin/POSIX sockets, SwiftTerm

**Spec:** `docs/superpowers/specs/2026-03-16-inline-notifications-design.md`

---

## File Map

**Create:**
- `Sources/TermGrid/Notifications/AgentSignal.swift` — `SocketPayload`, `AgentSignal`, `SessionType`, `AgentType`, `EventType`
- `Sources/TermGrid/Notifications/MessageParser.swift` — `MessageParser.extractSummary(from:)`
- `Sources/TermGrid/Notifications/SocketServer.swift` — Unix domain socket listener
- `Sources/TermGrid/Notifications/NotificationManager.swift` — UNNotification lifecycle + delegate
- `Sources/TermGrid/Notifications/HookInstaller.swift` — hook script deployment + agent config setup
- `Tests/TermGridTests/MessageParserTests.swift` — MessageParser unit tests
- `Tests/TermGridTests/AgentSignalTests.swift` — SocketPayload/AgentSignal tests
- `Tests/TermGridTests/SocketServerTests.swift` — SocketServer unit tests

**Modify:**
- `Sources/TermGrid/Terminal/TerminalSession.swift` — add `sessionType` param, inject env vars
- `Sources/TermGrid/Terminal/TerminalSessionManager.swift` — pass `SessionType` to `TerminalSession`
- `Sources/TermGrid/TermGridApp.swift` — wire NotificationManager + SocketServer on launch

---

## Chunk 1: Models & MessageParser

### Task 1: AgentSignal Models

**Files:**
- Create: `Sources/TermGrid/Notifications/AgentSignal.swift`
- Test: `Tests/TermGridTests/AgentSignalTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TermGridTests/AgentSignalTests.swift`:

```swift
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

    @Test func socketPayloadWithInvalidSessionTypeReturnsNil() throws {
        let json = """
        {"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"tertiary","agentType":"claudeCode","eventType":"complete","message":"hello"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(SocketPayload.self, from: json)
        let signal = AgentSignal(from: payload)
        #expect(signal == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentSignalTests 2>&1 | tail -5`
Expected: compilation error — `SocketPayload`, `AgentSignal`, etc. not defined

- [ ] **Step 3: Write the implementation**

Create `Sources/TermGrid/Notifications/AgentSignal.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AgentSignalTests 2>&1 | tail -5`
Expected: all tests pass (will need MessageParser first — see Task 2)

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Notifications/AgentSignal.swift Tests/TermGridTests/AgentSignalTests.swift
git commit -m "feat: add AgentSignal and SocketPayload models"
```

---

### Task 2: MessageParser

**Files:**
- Create: `Sources/TermGrid/Notifications/MessageParser.swift`
- Test: `Tests/TermGridTests/MessageParserTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TermGridTests/MessageParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MessageParserTests 2>&1 | tail -5`
Expected: compilation error — `MessageParser` not defined

- [ ] **Step 3: Write the implementation**

Create `Sources/TermGrid/Notifications/MessageParser.swift`:

```swift
import Foundation

enum MessageParser {
    static func extractSummary(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Split into sentences by `. `, `? `, `! ` or end-of-string
        let pattern = #"[^.!?]*[.!?]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              !trimmed.isEmpty else {
            return trimmed
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, range: range)

        guard !matches.isEmpty else {
            // No sentence-ending punctuation — return whole message
            return trimmed
        }

        // Find the last sentence ending with `?`
        for match in matches.reversed() {
            if let swiftRange = Range(match.range, in: trimmed) {
                let sentence = String(trimmed[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if sentence.hasSuffix("?") {
                    return sentence
                }
            }
        }

        // No question found — return last sentence
        if let lastMatch = matches.last,
           let swiftRange = Range(lastMatch.range, in: trimmed) {
            return String(trimmed[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MessageParserTests 2>&1 | tail -5`
Expected: all tests pass

- [ ] **Step 5: Also run AgentSignal tests (they depend on MessageParser)**

Run: `swift test --filter "AgentSignalTests|MessageParserTests" 2>&1 | tail -10`
Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Notifications/MessageParser.swift Tests/TermGridTests/MessageParserTests.swift
git commit -m "feat: add MessageParser for notification summary extraction"
```

---

## Chunk 2: SocketServer

### Task 3: SocketServer

**Files:**
- Create: `Sources/TermGrid/Notifications/SocketServer.swift`
- Test: `Tests/TermGridTests/SocketServerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TermGridTests/SocketServerTests.swift`:

```swift
@testable import TermGrid
import Testing
import Foundation
import Synchronization

@Suite("SocketServer Tests")
struct SocketServerTests {

    private func tempSocketPath() -> String {
        "/tmp/termgrid-test-\(UUID().uuidString).sock"
    }

    @Test func createsSocketFileOnStart() async throws {
        let path = tempSocketPath()
        let server = SocketServer(socketPath: path)
        server.start { _ in }
        // Give server time to bind
        try await Task.sleep(for: .milliseconds(100))
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
    }

    @Test func removesSocketFileOnStop() async throws {
        let path = tempSocketPath()
        let server = SocketServer(socketPath: path)
        server.start { _ in }
        try await Task.sleep(for: .milliseconds(100))
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func removesStaleSocketOnStart() async throws {
        let path = tempSocketPath()
        // Create a stale file
        FileManager.default.createFile(atPath: path, contents: nil)
        #expect(FileManager.default.fileExists(atPath: path))
        let server = SocketServer(socketPath: path)
        server.start { _ in }
        try await Task.sleep(for: .milliseconds(100))
        // Should have replaced it with a real socket
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
    }

    @Test func receivesJSONPayload() async throws {
        let path = tempSocketPath()
        let server = SocketServer(socketPath: path)

        let expectation = Mutex<SocketPayload?>(nil)

        server.start { payload in
            expectation.withLock { $0 = payload }
        }
        try await Task.sleep(for: .milliseconds(100))

        // Connect and send JSON via socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { cstr in
                strcpy(ptr, cstr)
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        let json = #"{"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"primary","agentType":"claudeCode","eventType":"complete","message":"Done"}"# + "\n"
        json.withCString { cstr in
            _ = Darwin.write(fd, cstr, strlen(cstr))
        }

        // Wait for processing
        try await Task.sleep(for: .milliseconds(200))
        let received = expectation.withLock { $0 }
        #expect(received != nil)
        #expect(received?.cellID == "550e8400-e29b-41d4-a716-446655440000")
        #expect(received?.message == "Done")
        server.stop()
    }

    @Test func handlesMalformedJSONWithoutCrashing() async throws {
        let path = tempSocketPath()
        let server = SocketServer(socketPath: path)
        let received = Mutex(false)
        server.start { _ in received.withLock { $0 = true } }
        try await Task.sleep(for: .milliseconds(100))

        // Send garbage
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { cstr in strcpy(ptr, cstr) }
        }
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let garbage = "not json at all\n"
        garbage.withCString { cstr in _ = Darwin.write(fd, cstr, strlen(cstr)) }

        try await Task.sleep(for: .milliseconds(200))
        #expect(!received.withLock { $0 })  // callback should not have been called
        server.stop()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SocketServerTests 2>&1 | tail -5`
Expected: compilation error — `SocketServer` not defined

- [ ] **Step 3: Write the implementation**

Create `Sources/TermGrid/Notifications/SocketServer.swift`:

```swift
import Foundation
import Darwin

final class SocketServer: @unchecked Sendable {
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.termgrid.socketserver", qos: .utility)
    private let clientQueue = DispatchQueue(label: "com.termgrid.socketserver.clients", qos: .utility, attributes: .concurrent)
    private var serverFD: Int32 = -1
    private var isRunning = false

    init(socketPath: String = NSHomeDirectory() + "/.termgrid/notify.sock") {
        self.socketPath = socketPath
    }

    func start(onPayload: @escaping (SocketPayload) -> Void) {
        queue.async { [self] in
            // Remove stale socket
            unlink(socketPath)

            // Ensure parent directory exists
            let dir = (socketPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            // Create socket
            serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
            guard serverFD >= 0 else { return }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                socketPath.withCString { cstr in strcpy(ptr, cstr) }
            }

            let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.bind(serverFD, sockPtr, addrLen)
                }
            }
            guard bindResult == 0 else {
                close(serverFD)
                serverFD = -1
                return
            }

            guard Darwin.listen(serverFD, 5) == 0 else {
                close(serverFD)
                serverFD = -1
                return
            }

            isRunning = true

            while isRunning {
                let clientFD = Darwin.accept(serverFD, nil, nil)
                guard clientFD >= 0 else {
                    if !isRunning { break }
                    continue
                }

                clientQueue.async {
                    self.handleClient(fd: clientFD, onPayload: onPayload)
                }
            }
        }
    }

    func stop() {
        isRunning = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    private func handleClient(fd: Int32, onPayload: @escaping (SocketPayload) -> Void) {
        defer { close(fd) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            data.append(contentsOf: buffer[0..<bytesRead])
            if buffer[0..<bytesRead].contains(UInt8(ascii: "\n")) { break }
        }

        // Parse each newline-delimited JSON
        let lines = data.split(separator: UInt8(ascii: "\n"))
        for line in lines {
            guard let payload = try? JSONDecoder().decode(SocketPayload.self, from: Data(line)) else {
                continue
            }
            onPayload(payload)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SocketServerTests 2>&1 | tail -10`
Expected: all tests pass

- [ ] **Step 5: Run all tests to check no V1 regression**

Run: `swift test 2>&1 | tail -10`
Expected: all existing + new tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Notifications/SocketServer.swift Tests/TermGridTests/SocketServerTests.swift
git commit -m "feat: add SocketServer for Unix domain socket IPC"
```

---

## Chunk 3: NotificationManager

### Task 4: NotificationManager

**Files:**
- Create: `Sources/TermGrid/Notifications/NotificationManager.swift`

Note: `UNUserNotificationCenter` is difficult to unit test in isolation (requires real notification center). The notification manager will be tested via manual integration tests (Task 8). The core routing logic depends on `TerminalSessionManager` which is `@MainActor`, making it hard to mock. Instead we test the observable behavior end-to-end.

- [ ] **Step 1: Write the implementation**

Create `Sources/TermGrid/Notifications/NotificationManager.swift`:

```swift
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let sessionManager: TerminalSessionManager
    private let store: WorkspaceStore

    static let categoryIdentifier = "AGENT_MESSAGE"
    static let replyActionIdentifier = "REPLY_ACTION"
    static let dismissActionIdentifier = "DISMISS_ACTION"

    init(sessionManager: TerminalSessionManager, store: WorkspaceStore) {
        self.sessionManager = sessionManager
        self.store = store
        super.init()
    }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Request permission
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { print("[TermGrid] Notification permission error: \(error)") }
        }

        // Register category
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
        let content = UNMutableNotificationContent()

        // Look up cell for labels
        if let cell = store.workspace.cells.first(where: { $0.id == signal.cellID }) {
            content.title = cell.label.isEmpty ? "TermGrid" : cell.label
            let termLabel = signal.sessionType == .primary ? cell.terminalLabel : cell.splitTerminalLabel
            if !termLabel.isEmpty {
                content.subtitle = termLabel
            }
        } else {
            content.title = "TermGrid"
        }

        // Body: summary first, then full message for expanded view
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

        guard response.actionIdentifier == Self.replyActionIdentifier,
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
                // Session gone — notify user
                let content = UNMutableNotificationContent()
                content.title = "TermGrid"
                content.body = "Session no longer active — reply could not be delivered."
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                center.add(request)
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner even when app is in foreground
        completionHandler([.banner, .sound])
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: build succeeds

- [ ] **Step 3: Run all tests to check no regression**

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/Notifications/NotificationManager.swift
git commit -m "feat: add NotificationManager for macOS notification lifecycle"
```

---

## Chunk 4: Terminal Session Env Vars

### Task 5: Inject TERMGRID_CELL_ID and TERMGRID_SESSION_TYPE

**Files:**
- Modify: `Sources/TermGrid/Terminal/TerminalSession.swift`
- Modify: `Sources/TermGrid/Terminal/TerminalSessionManager.swift`

- [ ] **Step 1: Modify TerminalSession**

In `Sources/TermGrid/Terminal/TerminalSession.swift`, change the init to accept `sessionType` and inject env vars:

Replace the current init:
```swift
    init(cellID: UUID, workingDirectory: String) {
        self.cellID = cellID
        self.sessionID = UUID()
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.nativeBackgroundColor = Theme.terminalBackground
        terminalView.nativeForegroundColor = Theme.terminalForeground
        terminalView.caretColor = Theme.terminalCursor

        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: nil,
            execName: nil,
            currentDirectory: workingDirectory
        )
    }
```

With:
```swift
    let sessionType: SessionType

    init(cellID: UUID, workingDirectory: String, sessionType: SessionType = .primary) {
        self.cellID = cellID
        self.sessionID = UUID()
        self.sessionType = sessionType
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.nativeBackgroundColor = Theme.terminalBackground
        terminalView.nativeForegroundColor = Theme.terminalForeground
        terminalView.caretColor = Theme.terminalCursor

        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TERMGRID_CELL_ID=\(cellID.uuidString)")
        env.append("TERMGRID_SESSION_TYPE=\(sessionType.rawValue)")

        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env,
            execName: nil,
            currentDirectory: workingDirectory
        )
    }
```

Also add `import SwiftTerm` at the top if not already there (it is — `LocalProcessTerminalView` requires it).

- [ ] **Step 2: Modify TerminalSessionManager**

In `Sources/TermGrid/Terminal/TerminalSessionManager.swift`, update `createSession` and `createSplitSession` to pass the correct `SessionType`:

Change `createSession`:
```swift
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory)
```
to:
```swift
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory, sessionType: .primary)
```

Change `createSplitSession`:
```swift
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory)
```
to:
```swift
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory, sessionType: .split)
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: build succeeds

- [ ] **Step 4: Run all tests including existing TerminalSessionManager tests**

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass (existing tests use default `.primary` — no breakage)

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Terminal/TerminalSession.swift Sources/TermGrid/Terminal/TerminalSessionManager.swift
git commit -m "feat: inject TERMGRID_CELL_ID and TERMGRID_SESSION_TYPE env vars into PTY"
```

---

## Chunk 5: App Wiring & Hook Installation

### Task 6: Wire NotificationManager + SocketServer in TermGridApp

**Files:**
- Modify: `Sources/TermGrid/TermGridApp.swift`

- [ ] **Step 1: Modify TermGridApp**

In `Sources/TermGrid/TermGridApp.swift`, add the notification subsystem wiring. Add properties and startup logic:

Add after the existing `@State` properties:
```swift
    private var notificationManager: NotificationManager?
    private var socketServer: SocketServer?
```

Add a new method and call it from `.onAppear`:
```swift
    private mutating func startNotificationSubsystem() {
        let manager = NotificationManager(sessionManager: sessionManager, store: store)
        manager.setup()
        self.notificationManager = manager

        let server = SocketServer()
        server.start { [manager] payload in
            guard let signal = AgentSignal(from: payload) else { return }
            Task { @MainActor in
                manager.postNotification(for: signal)
            }
        }
        self.socketServer = server
    }
```

Update `.onAppear` to call it:
```swift
    .onAppear {
        NSApp.activate(ignoringOtherApps: true)
        startNotificationSubsystem()
    }
```

Update the `willTerminateNotification` handler to stop the socket server:
```swift
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
        store.flush()
        sessionManager.killAll()
        socketServer?.stop()
    }
```

Note: Since `TermGridApp` is a struct, we need to handle the mutability carefully. The `notificationManager` and `socketServer` should be stored in a way that persists across body evaluations. Use a simple holder class:

```swift
@MainActor
private final class NotificationSubsystem {
    var manager: NotificationManager?
    var server: SocketServer?
}
```

And use `@State private var notificationSubsystem = NotificationSubsystem()` instead.

The full modified `TermGridApp.swift`:

```swift
import SwiftUI
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }
}

@MainActor
private final class NotificationSubsystem {
    var manager: NotificationManager?
    var server: SocketServer?
}

@main
struct TermGridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()
    @State private var sessionManager = TerminalSessionManager()
    @State private var notificationSubsystem = NotificationSubsystem()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        Window("TermGrid", id: "main") {
            ContentView(store: store, sessionManager: sessionManager)
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    startNotificationSubsystem()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        store.flush()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flush()
                    sessionManager.killAll()
                    notificationSubsystem.server?.stop()
                }
        }
        .defaultSize(width: 900, height: 600)
    }

    private func startNotificationSubsystem() {
        guard notificationSubsystem.manager == nil else { return }

        let manager = NotificationManager(sessionManager: sessionManager, store: store)
        manager.setup()
        notificationSubsystem.manager = manager

        let server = SocketServer()
        server.start { payload in
            guard let signal = AgentSignal(from: payload) else { return }
            Task { @MainActor in
                manager.postNotification(for: signal)
            }
        }
        notificationSubsystem.server = server
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: build succeeds

- [ ] **Step 3: Run all tests**

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/TermGridApp.swift
git commit -m "feat: wire NotificationManager and SocketServer into app lifecycle"
```

---

### Task 7: Hook Scripts & HookInstaller

**Files:**
- Create: `Sources/TermGrid/Notifications/HookInstaller.swift`

- [ ] **Step 1: Write the implementation**

Create `Sources/TermGrid/Notifications/HookInstaller.swift`:

```swift
import Foundation

enum HookInstaller {
    private static let hooksDir = NSHomeDirectory() + "/.termgrid/hooks"
    private static let versionFile = hooksDir + "/.version"
    private static let currentVersion = "1"

    static func installIfNeeded() {
        let fm = FileManager.default

        // Check version
        if let existingVersion = try? String(contentsOfFile: versionFile, encoding: .utf8),
           existingVersion.trimmingCharacters(in: .whitespacesAndNewlines) == currentVersion {
            return
        }

        // Create hooks directory
        try? fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        // Write Claude Code hook
        let claudeHook = """
        #!/bin/bash
        PAYLOAD=$(cat)
        EVENT=$(echo "$PAYLOAD" | jq -r '.hook_event_name')

        if [ "$EVENT" = "Stop" ]; then
          MESSAGE=$(echo "$PAYLOAD" | jq -r '.last_assistant_message // ""')
          EVENT_TYPE="complete"
        else
          MESSAGE=$(echo "$PAYLOAD" | jq -r '.message // ""')
          EVENT_TYPE="needsInput"
        fi

        echo "{\\"cellID\\":\\"$TERMGRID_CELL_ID\\",\\"sessionType\\":\\"$TERMGRID_SESSION_TYPE\\",\\"agentType\\":\\"claudeCode\\",\\"eventType\\":\\"$EVENT_TYPE\\",\\"message\\":$(echo "$MESSAGE" | jq -Rs .)}" | nc -U ~/.termgrid/notify.sock
        """
        let claudePath = hooksDir + "/termgrid-notify-claude.sh"
        try? claudeHook.write(toFile: claudePath, atomically: true, encoding: .utf8)
        chmod(claudePath, 0o755)

        // Write Codex hook
        let codexHook = """
        #!/bin/bash
        PAYLOAD="$1"
        MESSAGE=$(echo "$PAYLOAD" | jq -r '.["last-assistant-message"] // ""')

        echo "{\\"cellID\\":\\"$TERMGRID_CELL_ID\\",\\"sessionType\\":\\"$TERMGRID_SESSION_TYPE\\",\\"agentType\\":\\"codex\\",\\"eventType\\":\\"complete\\",\\"message\\":$(echo "$MESSAGE" | jq -Rs .)}" | nc -U ~/.termgrid/notify.sock
        """
        let codexPath = hooksDir + "/termgrid-notify-codex.sh"
        try? codexHook.write(toFile: codexPath, atomically: true, encoding: .utf8)
        chmod(codexPath, 0o755)

        // Write version marker
        try? currentVersion.write(toFile: versionFile, atomically: true, encoding: .utf8)
    }

    private static func chmod(_ path: String, _ mode: mode_t) {
        Darwin.chmod(path, mode)
    }

    /// Check if jq is available (required by hook scripts)
    static var isJqInstalled: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["jq"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Agent Config Setup

    /// Merge TermGrid hook entries into Claude Code's settings.json
    static func setupClaudeCodeHooks() {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        let hookCommand = hooksDir + "/termgrid-notify-claude.sh"
        let fm = FileManager.default

        // Ensure .claude directory exists
        let claudeDir = NSHomeDirectory() + "/.claude"
        try? fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        // Load existing settings or start fresh
        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Build hook entry
        let hookEntry: [String: Any] = [
            "matcher": "*",
            "hooks": [["type": "command", "command": hookCommand]]
        ]

        // Merge into hooks (preserve existing hooks for other events)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in ["Stop", "Notification"] {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            // Remove any existing TermGrid hooks
            eventHooks.removeAll { entry in
                if let entryHooks = entry["hooks"] as? [[String: Any]] {
                    return entryHooks.contains { ($0["command"] as? String)?.contains("termgrid") == true }
                }
                return false
            }
            eventHooks.append(hookEntry)
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks

        // Write back
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    /// Merge TermGrid notify entry into Codex's config.toml
    static func setupCodexHooks() {
        let configPath = NSHomeDirectory() + "/.codex/config.toml"
        let hookCommand = hooksDir + "/termgrid-notify-codex.sh"
        let fm = FileManager.default

        // Ensure .codex directory exists
        let codexDir = NSHomeDirectory() + "/.codex"
        try? fm.createDirectory(atPath: codexDir, withIntermediateDirectories: true)

        // Read existing config
        var config = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""

        // Remove existing [notify] section with termgrid command
        if config.contains("[notify]") {
            let lines = config.components(separatedBy: "\n")
            var filtered: [String] = []
            var inNotifySection = false
            for line in lines {
                if line.trimmingCharacters(in: .whitespace) == "[notify]" {
                    inNotifySection = true
                    continue
                }
                if inNotifySection {
                    if line.hasPrefix("[") { // new section
                        inNotifySection = false
                        filtered.append(line)
                    } else if line.contains("termgrid") {
                        continue // skip termgrid entries
                    } else if !line.trimmingCharacters(in: .whitespace).isEmpty {
                        // Non-termgrid entry in notify — keep it
                        // (but re-add [notify] header if we haven't)
                        if !filtered.contains("[notify]") {
                            filtered.append("[notify]")
                        }
                        filtered.append(line)
                    }
                } else {
                    filtered.append(line)
                }
            }
            config = filtered.joined(separator: "\n")
        }

        // Append our [notify] section
        if !config.hasSuffix("\n") && !config.isEmpty { config += "\n" }
        config += "\n[notify]\ncommand = \"\(hookCommand)\"\n"

        try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 2: Call HookInstaller from app startup**

In `Sources/TermGrid/TermGridApp.swift`, add to `startNotificationSubsystem()`:

After `guard notificationSubsystem.manager == nil else { return }`, add:
```swift
        HookInstaller.installIfNeeded()
        HookInstaller.setupClaudeCodeHooks()
        HookInstaller.setupCodexHooks()
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: build succeeds

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Notifications/HookInstaller.swift Sources/TermGrid/TermGridApp.swift
git commit -m "feat: add HookInstaller for automatic hook script deployment"
```

---

## Chunk 6: Integration Testing & Final Verification

### Task 8: Manual Integration Test

- [ ] **Step 1: Run the app**

Run: `swift run`
Expected: TermGrid launches, socket created at `~/.termgrid/notify.sock`, hook scripts written to `~/.termgrid/hooks/`

- [ ] **Step 2: Verify socket exists**

Run: `ls -la ~/.termgrid/notify.sock`
Expected: socket file exists

- [ ] **Step 3: Verify hook scripts exist and are executable**

Run: `ls -la ~/.termgrid/hooks/`
Expected: `termgrid-notify-claude.sh` and `termgrid-notify-codex.sh` with execute permission

- [ ] **Step 4: Send a test notification via socket**

With TermGrid running, in another terminal:

```bash
echo '{"cellID":"<paste-a-real-cell-id-from-TermGrid>","sessionType":"primary","agentType":"claudeCode","eventType":"complete","message":"I have completed the refactoring. All 30 tests pass. Shall I continue to the next task?"}' | nc -U ~/.termgrid/notify.sock
```

Expected: macOS notification appears with:
- Title: cell label (or "TermGrid" if no label set)
- Subtitle: terminal label (if set)
- Body: "Shall I continue to the next task?" followed by full message

- [ ] **Step 5: Test reply routing**

Reply to the notification using the inline text input.
Expected: reply text + carriage return appears in the terminal PTY

- [ ] **Step 6: Test dismiss**

Send another test notification, click Dismiss.
Expected: notification dismissed, no app activation

- [ ] **Step 7: Run full test suite one final time**

Run: `swift test 2>&1 | tail -15`
Expected: all tests pass (V1 + V2)

- [ ] **Step 8: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: integration test fixes for inline notification system"
```
