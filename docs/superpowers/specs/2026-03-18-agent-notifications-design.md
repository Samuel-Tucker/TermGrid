# Pack 013: Agent Notifications — Design Spec

**Date:** 2026-03-18
**Status:** Approved
**Source:** packs/013-agent-notifications.md (Codex-reviewed)
**Codex Plan Review:** 5 critical findings integrated

## Problem

Users running long AI agent tasks switch away and miss when tasks complete or need attention.

## Solution

Monitor terminal output for patterns, show visual indicators (notification dot + border pulse) and macOS system notifications.

## Output Scanning

### Pattern Matcher

New `OutputPatternMatcher` class. Scans line-buffered terminal output for patterns:

| Pattern | Severity | Color |
|---------|----------|-------|
| `Build complete!` | success | `#75BE95` (Theme.staged) |
| `Test run with .* passed` | success | `#75BE95` |
| `^error:` (anchored to line start) | error | `#E06C75` (Theme.error) |
| `^FAIL` (anchored to line start) | error | `#E06C75` |
| `^[?] ` (question after prompt) | attention | Theme.accent |

Patterns match against **normalized text** (ANSI stripped), not raw bytes.

### Line Buffering (chunk boundary fix)

Raw PTY output arrives in arbitrary chunks that can split lines. The matcher must buffer partial lines:
- Accumulate bytes until a newline is found
- Strip ANSI escape sequences from each complete line
- Scan the cleaned line against patterns
- Keep the incomplete trailing portion for the next chunk

### Threading (MainActor safety)

`LoggingTerminalView.dataReceived` runs on SwiftTerm's dispatch queue, NOT on MainActor. The pattern matcher scans in the callback thread, then dispatches matched results to MainActor:

```swift
override func dataReceived(slice: ArraySlice<UInt8>) {
    super.dataReceived(slice: slice)
    if let match = patternMatcher.scan(slice) {
        Task { @MainActor in
            onPatternMatch?(match)
        }
    }
}
```

## Notification State

### Per-Session State on TerminalSessionManager

Add observable notification state keyed by cellID:

```swift
// On TerminalSessionManager
var notificationStates: [UUID: CellNotificationState] = [:]
```

```swift
@MainActor @Observable
final class CellNotificationState {
    var severity: NotificationSeverity? = nil  // nil = no notification
    var matchedPattern: String = ""
    var timestamp: Date? = nil
    var sourcePane: SessionType = .primary
}

enum NotificationSeverity {
    case success, error, attention
}
```

### Event Flow

`LoggingTerminalView.dataReceived` → `OutputPatternMatcher.scan()` → `Task { @MainActor }` → `TerminalSessionManager.notificationStates[cellID]` → CellView reads state and renders dot/pulse.

The `onPatternMatch` callback is set on `LoggingTerminalView` by `TerminalSession.init`, which knows the `cellID`.

### Clearing

**Clear on terminal focus** (not scroll-to-bottom — SwiftTerm has no scroll position delegate). When the user clicks into or Ctrl+Tabs to a terminal, clear its notification state. This is simpler and avoids the missing scroll callback issue.

Implement: in `ContentView.updateFocusedCell()`, when `focusedCellID` changes, clear the notification for the newly focused cell.

## UI

### Notification Dot

6px colored circle to the **left** of the cell label in the header. Only visible when `severity != nil`.

```swift
if let severity = sessionManager.notificationStates[cell.id]?.severity {
    Circle()
        .fill(severity.color)
        .frame(width: 6, height: 6)
}
```

### Border Pulse

3-second accent-color glow on the cell border when a notification fires. Use `.overlay` with animated opacity:

```swift
RoundedRectangle(cornerRadius: 8)
    .stroke(Theme.accent, lineWidth: 2)
    .opacity(showBorderPulse ? 1 : 0)
    .animation(.easeInOut(duration: 1.5).repeatCount(2, autoreverses: true), value: showBorderPulse)
```

### macOS System Notification

For `error` and `attention` severity only. Use `UNUserNotificationCenter` (existing `NotificationManager` infrastructure). Add a new method that accepts pattern-based notifications directly (not only socket `AgentSignal`):

```swift
func postPatternNotification(cellLabel: String, pattern: String, severity: NotificationSeverity)
```

This is independent of the existing socket-based notification path.

## Theme Addition

```swift
static let error = Color(hex: "#E06C75")
```

## Implementation Order

1. Add `error` color to Theme
2. Create `OutputPatternMatcher` (line buffering, ANSI stripping, pattern matching)
3. Create `CellNotificationState` + `NotificationSeverity`
4. Add `onPatternMatch` callback to `LoggingTerminalView`
5. Wire pattern matcher into `TerminalSession.init`
6. Add notification state to `TerminalSessionManager`
7. Render notification dot + border pulse in CellView
8. Clear notification on cell focus in ContentView
9. Wire macOS system notifications for error/attention
10. Add command palette entry for clearing all notifications
