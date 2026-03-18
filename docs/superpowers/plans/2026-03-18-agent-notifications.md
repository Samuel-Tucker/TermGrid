# Pack 013: Agent Notifications Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Monitor terminal output for patterns and show visual indicators (notification dot, border pulse) plus macOS system notifications.

**Architecture:** `OutputPatternMatcher` scans line-buffered output in `LoggingTerminalView.dataReceived`. Matches dispatch to MainActor via `TerminalSession.onPatternMatch` callback, updating `CellNotificationState` on `TerminalSessionManager`. CellView reads state for dot/pulse rendering.

**Tech Stack:** Swift, SwiftUI, UserNotifications, Swift Testing

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `Sources/TermGrid/Theme.swift` | Add `error` color |
| Create | `Sources/TermGrid/Models/OutputPatternMatcher.swift` | Line buffering, ANSI stripping, pattern matching |
| Create | `Sources/TermGrid/Models/CellNotificationState.swift` | Per-cell notification state + severity enum |
| Modify | `Sources/TermGrid/Terminal/LoggingTerminalView.swift` | Add `onPatternMatch` callback, wire pattern matcher |
| Modify | `Sources/TermGrid/Terminal/TerminalSession.swift` | Set up `onPatternMatch` callback on `LoggingTerminalView` |
| Modify | `Sources/TermGrid/Terminal/TerminalSessionManager.swift` | Add `notificationStates` dictionary |
| Modify | `Sources/TermGrid/Views/CellView.swift` | Render notification dot + border pulse |
| Modify | `Sources/TermGrid/Views/ContentView.swift` | Clear notification on cell focus |
| Create | `Tests/TermGridTests/OutputPatternMatcherTests.swift` | Pattern matching tests |

---

### Task 1: Theme + OutputPatternMatcher + Tests

**Files:**
- Modify: `Sources/TermGrid/Theme.swift`
- Create: `Sources/TermGrid/Models/OutputPatternMatcher.swift`
- Create: `Tests/TermGridTests/OutputPatternMatcherTests.swift`

- [ ] **Step 1: Add error color to Theme**

In `Sources/TermGrid/Theme.swift`, add in the Git section (after `staged`):

```swift
static let error = Color(hex: "#E06C75")
```

- [ ] **Step 2: Write failing tests**

```swift
// Tests/TermGridTests/OutputPatternMatcherTests.swift
@testable import TermGrid
import Testing
import Foundation

@Suite("OutputPatternMatcher Tests")
struct OutputPatternMatcherTests {

    @Test func matchesBuildComplete() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("Build complete!\n".utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .success)
    }

    @Test func matchesTestPassed() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("✔ Test run with 42 tests in 5 suites passed after 0.3 seconds.\n".utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .success)
    }

    @Test func matchesErrorAtLineStart() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("error: cannot find module\n".utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .error)
    }

    @Test func doesNotMatchErrorMidLine() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("some text error: not at start\n".utf8))
        #expect(matches.isEmpty)
    }

    @Test func matchesFailAtLineStart() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("FAIL some test\n".utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .error)
    }

    @Test func noMatchOnNormalOutput() {
        var matcher = OutputPatternMatcher()
        let matches = matcher.processChunk(Array("sam@Mac ~ % ls\nfile1.txt\nfile2.txt\n".utf8))
        #expect(matches.isEmpty)
    }

    @Test func handlesChunkBoundaries() {
        var matcher = OutputPatternMatcher()
        // "Build complete!" split across two chunks
        let matches1 = matcher.processChunk(Array("Build comp".utf8))
        #expect(matches1.isEmpty) // no newline yet
        let matches2 = matcher.processChunk(Array("lete!\n".utf8))
        #expect(matches2.count == 1)
        #expect(matches2[0].severity == .success)
    }

    @Test func stripsAnsiEscapes() {
        var matcher = OutputPatternMatcher()
        // ANSI colored "error:" — ESC[31merror:ESC[0m message
        let ansi = "\u{1b}[31merror:\u{1b}[0m something broke\n"
        let matches = matcher.processChunk(Array(ansi.utf8))
        #expect(matches.count == 1)
        #expect(matches[0].severity == .error)
    }

    @Test func multipleMatchesInOneChunk() {
        var matcher = OutputPatternMatcher()
        let chunk = "Build complete!\nerror: but then this\n"
        let matches = matcher.processChunk(Array(chunk.utf8))
        #expect(matches.count == 2)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter OutputPatternMatcherTests 2>&1 | tail -20`
Expected: FAIL — type not found

- [ ] **Step 4: Write OutputPatternMatcher**

```swift
// Sources/TermGrid/Models/OutputPatternMatcher.swift
import Foundation

enum NotificationSeverity {
    case success, error, attention

    var color: String {
        switch self {
        case .success: return "#75BE95"
        case .error: return "#E06C75"
        case .attention: return "#C4A574"
        }
    }
}

struct PatternMatch {
    let severity: NotificationSeverity
    let pattern: String
    let line: String
}

struct OutputPatternMatcher {
    private var lineBuffer: [UInt8] = []

    private static let patterns: [(regex: String, severity: NotificationSeverity)] = [
        ("Build complete!", .success),
        ("Test run with .* passed", .success),
        ("^error:", .error),
        ("^FAIL", .error),
    ]

    /// Process a chunk of raw bytes. Returns any pattern matches found in complete lines.
    mutating func processChunk(_ bytes: [UInt8]) -> [PatternMatch] {
        var matches: [PatternMatch] = []
        lineBuffer.append(contentsOf: bytes)

        while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) { // \n
            let lineBytes = Array(lineBuffer[lineBuffer.startIndex...newlineIndex])
            lineBuffer.removeFirst(lineBytes.count)

            guard let rawLine = String(bytes: lineBytes, encoding: .utf8) else { continue }
            let cleanLine = Self.stripAnsi(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanLine.isEmpty else { continue }

            for (pattern, severity) in Self.patterns {
                if let _ = cleanLine.range(of: pattern, options: .regularExpression) {
                    matches.append(PatternMatch(severity: severity, pattern: pattern, line: cleanLine))
                    break // one match per line
                }
            }
        }

        return matches
    }

    /// Strip ANSI escape sequences from a string.
    static func stripAnsi(_ text: String) -> String {
        // Matches ESC[ ... m (SGR), ESC[ ... H (cursor), and other CSI sequences
        text.replacingOccurrences(
            of: "\\x1b\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter OutputPatternMatcherTests 2>&1 | tail -20`
Expected: All 9 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Theme.swift Sources/TermGrid/Models/OutputPatternMatcher.swift Tests/TermGridTests/OutputPatternMatcherTests.swift
git commit -m "feat: add OutputPatternMatcher with line buffering and ANSI stripping"
```

---

### Task 2: CellNotificationState + Wire into Sessions

**Files:**
- Create: `Sources/TermGrid/Models/CellNotificationState.swift`
- Modify: `Sources/TermGrid/Terminal/LoggingTerminalView.swift`
- Modify: `Sources/TermGrid/Terminal/TerminalSession.swift`
- Modify: `Sources/TermGrid/Terminal/TerminalSessionManager.swift`

- [ ] **Step 1: Create CellNotificationState**

```swift
// Sources/TermGrid/Models/CellNotificationState.swift
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

        // Border pulse auto-clears after 3 seconds
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
```

- [ ] **Step 2: Add onPatternMatch callback to LoggingTerminalView**

In `Sources/TermGrid/Terminal/LoggingTerminalView.swift`, add:

```swift
/// Callback for pattern matches. Called from SwiftTerm's dispatch queue — NOT MainActor.
var onPatternMatch: ((PatternMatch) -> Void)? = nil
private var patternMatcher = OutputPatternMatcher()
```

Update `dataReceived`:

```swift
override func dataReceived(slice: ArraySlice<UInt8>) {
    ptyLog.append(contentsOf: slice)

    if ptyLog.count > Self.maxLogSize {
        let excess = ptyLog.count - Self.maxLogSize
        ptyLog.removeFirst(excess)
    }

    // Scan for notification patterns
    if let callback = onPatternMatch {
        let matches = patternMatcher.processChunk(Array(slice))
        for match in matches {
            callback(match)
        }
    }

    super.dataReceived(slice: slice)
}
```

- [ ] **Step 3: Wire callback in TerminalSession**

In `Sources/TermGrid/Terminal/TerminalSession.swift`, add a public callback property:

```swift
var onNotification: ((PatternMatch) -> Void)? = nil
```

In `init`, after setting terminal colors and before `if startImmediately`, wire the callback:

```swift
terminalView.onPatternMatch = { [weak self] match in
    Task { @MainActor in
        self?.onNotification?(match)
    }
}
```

- [ ] **Step 4: Add notificationStates to TerminalSessionManager**

In `Sources/TermGrid/Terminal/TerminalSessionManager.swift`, add after `vaultKeys`:

```swift
var notificationStates: [UUID: CellNotificationState] = [:]

func notificationState(for cellID: UUID) -> CellNotificationState {
    if let existing = notificationStates[cellID] {
        return existing
    }
    let state = CellNotificationState()
    notificationStates[cellID] = state
    return state
}
```

Update `createSession` to wire the notification callback:

After `sessions[cellID] = session`, add:

```swift
let state = notificationState(for: cellID)
session.onNotification = { match in
    state.trigger(severity: match.severity, pattern: match.pattern)
}
```

Do the same for `createSplitSession`.

- [ ] **Step 5: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Models/CellNotificationState.swift Sources/TermGrid/Terminal/LoggingTerminalView.swift Sources/TermGrid/Terminal/TerminalSession.swift Sources/TermGrid/Terminal/TerminalSessionManager.swift
git commit -m "feat: wire notification state from terminal output to session manager"
```

---

### Task 3: Render Notification Dot + Border Pulse in CellView

**Files:**
- Modify: `Sources/TermGrid/Views/CellView.swift`
- Modify: `Sources/TermGrid/Views/ContentView.swift`

- [ ] **Step 1: Pass notification state to CellView**

In ContentView, update the CellView call to pass the notification state. CellView doesn't need a new parameter — it can access the notification state via the sessionManager if we pass it. However, the simplest approach: pass the `CellNotificationState` as a new property.

Add to CellView struct:
```swift
let notificationState: CellNotificationState
```

In ContentView's CellView instantiation, add:
```swift
notificationState: sessionManager.notificationState(for: cell.id)
```

- [ ] **Step 2: Add notification dot to header**

In CellView's `headerView`, add the dot before the label (before the `if isEditingLabel` block):

```swift
// Notification dot
if notificationState.severity != nil {
    Circle()
        .fill(notificationDotColor)
        .frame(width: 6, height: 6)
}
```

Add helper:
```swift
private var notificationDotColor: Color {
    switch notificationState.severity {
    case .success: return Theme.staged
    case .error: return Theme.error
    case .attention: return Theme.accent
    case .none: return .clear
    }
}
```

- [ ] **Step 3: Add border pulse**

In CellView's body, add an overlay after the existing border overlay (around line 116):

```swift
.overlay(
    RoundedRectangle(cornerRadius: 8)
        .stroke(notificationDotColor, lineWidth: 2)
        .opacity(notificationState.showBorderPulse ? 1 : 0)
        .animation(.easeInOut(duration: 1.5).repeatCount(2, autoreverses: true), value: notificationState.showBorderPulse)
)
```

- [ ] **Step 4: Clear notification on cell focus**

In ContentView's `updateFocusedCell()`, add at the end (after setting `focusedCellID`):

```swift
// Clear notification for newly focused cell
if let id = focusedCellID {
    sessionManager.notificationState(for: id).clear()
}
```

- [ ] **Step 5: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Views/CellView.swift Sources/TermGrid/Views/ContentView.swift
git commit -m "feat: render notification dot and border pulse in CellView"
```

---

### Task 4: Manual Verification

- [ ] **Step 1: Build and launch**

Run: `swift build 2>&1 | tail -5`
Launch and test:
- Run `swift test` in a terminal cell — should see green dot on "Test run with ... passed"
- Run a failing command — should see red dot on "error:" output
- Click into the cell — dot should clear
- Border should pulse briefly on notification trigger

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass
