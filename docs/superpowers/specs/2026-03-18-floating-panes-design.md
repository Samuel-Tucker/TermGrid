# Pack 014: Floating Panes — Design Spec

**Date:** 2026-03-18
**Status:** Approved
**Source:** packs/014-floating-panes.md (Codex-reviewed)
**Codex Plan Review:** 5 critical findings integrated

## Problem

Users need a quick terminal for one-off commands without disrupting their grid layout.

## Solution

Floating terminal pane (Picture-in-Picture for terminals) triggered by `Cmd+Shift+F`.

## UI

- **Size:** Fixed 350x250 (no resize in V1)
- **Position:** Bottom-right of grid area, draggable within grid bounds via 24px title bar
- **Max:** 1 at a time
- **Contains:** Terminal + compose box only. No header icons, notes, splits.
- **Trigger:** `Cmd+Shift+F` (keyboard only, no toolbar button)
- **Dismiss:** X button on title bar, `Cmd+Shift+F` again, or Escape if compose empty

### Styling

- Background: `Theme.cellBackground`
- Border: `Theme.accent` (1px) — distinguishes from grid cells
- Corner radius: 12px
- Shadow: `shadow(radius: 12)`
- Title bar: `Theme.headerBackground` with "Quick Terminal" label + X button

## Session Model

### Floating Session on TerminalSessionManager

```swift
// Add to TerminalSessionManager
var floatingSession: TerminalSession? = nil

func createFloatingSession() -> TerminalSession {
    floatingSession?.kill()
    let session = TerminalSession(
        cellID: UUID(), // unique ID, not tied to any grid cell
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
        sessionType: .primary,
        environment: buildEnvironment()
    )
    floatingSession = session
    return session
}

func killFloatingSession() {
    floatingSession?.kill()
    floatingSession = nil
}
```

### Lifecycle Fix (killAll teardown)

`killAll()` must include the floating session:

```swift
func killAll() {
    for session in sessions.values { session.kill() }
    sessions.removeAll()
    for session in splitSessions.values { session.kill() }
    splitSessions.removeAll()
    splitDirections.removeAll()
    floatingSession?.kill()
    floatingSession = nil
}
```

App termination path (`TermGridApp.onReceive(willTerminate)`) already calls `sessionManager.killAll()`, so this is covered.

## FloatingPaneView

New SwiftUI view:

```swift
struct FloatingPaneView: View {
    let session: TerminalSession
    let onDismiss: () -> Void
    @State private var offset: CGSize = .zero
```

Contains:
- 24px title bar with "Quick Terminal" label + X button (draggable)
- `TerminalContainerView(session:)` for terminal
- `ComposeBox` for input
- Drag gesture on title bar only (not terminal body)
- `.onKeyPress(.escape)` dismisses if appropriate

## Overlay Mounting

Mount on `gridContent` in ContentView (NOT the root ZStack — avoids covering API locker):

```swift
private var gridContent: some View {
    GeometryReader { geo in
        // ... existing grid layout ...
    }
    .overlay(alignment: .bottomTrailing) {
        if showFloatingPane, let session = sessionManager.floatingSession {
            FloatingPaneView(session: session, onDismiss: {
                sessionManager.killFloatingSession()
                showFloatingPane = false
            })
            .padding(16)
        }
    }
}
```

## Keyboard Shortcut

### Cmd+Shift+F

Add to `TermGridApp.swift` Commands menu:

```swift
Button("Quick Terminal") {
    NotificationCenter.default.post(name: .toggleFloatingPane, object: nil)
}
.keyboardShortcut("f", modifiers: [.command, .shift])
```

Also add NSEvent fallback in ContentView's existing key monitor (alongside Cmd+Shift+P).

Add notification receiver in ContentView:
```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleFloatingPane)) { _ in
    if showFloatingPane {
        sessionManager.killFloatingSession()
        showFloatingPane = false
    } else {
        sessionManager.createFloatingSession()
        showFloatingPane = true
    }
}
```

## Focus

- Floating pane does NOT participate in Ctrl+Tab cell focus cycling
- Click into it to focus, click a grid cell to return focus
- When floating pane is focused, `focusedCellID` stays at its current value (or becomes nil) — command palette cell commands won't target the floating pane
- Escape dismisses if compose box is empty

## Implementation Order

1. Create `FloatingPaneView` (UI with drag gesture)
2. Add `floatingSession` + lifecycle to `TerminalSessionManager`
3. Add `showFloatingPane` state + overlay to ContentView
4. Add `Cmd+Shift+F` shortcut (Commands menu + NSEvent fallback)
5. Add notification name + receiver wiring
