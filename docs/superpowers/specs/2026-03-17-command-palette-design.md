# Pack 012: Command Palette — Design Spec

**Date:** 2026-03-17
**Status:** Approved
**Source:** packs/012-command-palette.md (Codex-reviewed, blind spots fixed)

## Problem

As TermGrid gains features, discoverability drops. Users need a single entry point to find and execute any action.

## Solution

Global command palette (`Cmd+Shift+P`) with three architectural prerequisites that benefit all future packs.

## Prerequisites

### 1. CellUIState Observable

Create `@MainActor @Observable` class per cell, replacing private `@State` in CellView:

```swift
@MainActor @Observable
final class CellUIState {
    var showNotes: Bool = true
    var showExplorer: Bool = false
    var showGit: Bool = false
    var showHiddenFiles: Bool = false
    var isCreatingNewItem: Bool = false
    var newItemIsFolder: Bool = false
}
```

**Ownership:** ContentView holds `[UUID: CellUIState]` dictionary. Each CellView receives its `CellUIState` instance. CellView reads/writes these instead of private `@State`.

**Why:** Command palette (and any future external control) needs to mutate cell panel states. Private `@State` is unreachable from outside the view.

### 2. Focused Cell Tracking

Add `focusedCellID: UUID?` on ContentView.

**Update mechanism:** Extend existing NSEvent monitor in CellView (currently handles Ctrl+Tab at lines 103-110). Walk responder chain from `NSApp.keyWindow?.firstResponder` upward to find which cell's container owns the responder. Update `focusedCellID` on each change.

**Why:** Palette needs to know which cell to scope commands to. Also enables future features that act on the focused cell.

### 3. Fix Cell-Scoped Notifications

`NotificationCenter.post(name: .focusNotesPanel, object: cell.id)` posts correctly, but NotesView subscriber ignores the `object:` parameter — all cells react.

**Fix:** Filter on cell ID in receiver:
```swift
.onReceive(NotificationCenter.default.publisher(for: .focusNotesPanel)) { notification in
    guard let targetID = notification.object as? UUID, targetID == cellID else { return }
    // focus the text view
}
```

## Command Palette UI

### Trigger
- Primary: `Cmd+Shift+P` via SwiftUI `Commands` / `.keyboardShortcut`
- Fallback: If SwiftUI commands don't intercept when terminal/compose NSView is first responder, use `NSEvent.addLocalMonitorForEvents` with explicit key detection
- Also: macOS menu item under `Commands` menu for discoverability

### Overlay
- Mount: `.overlay` on `WindowGroup` scene in TermGridApp.swift (approach A — above all content including toolbar)
- Size: 400px wide, max 300px tall
- Position: Centered in window
- Dismiss: Escape, click outside, select action

### Context
- Header shows "Cell: {label}" when a cell is focused, "Global" otherwise
- Cell-scoped commands only appear when a cell is focused

### Theme
- Background: `Theme.cellBackground` with `shadow(radius: 20)`
- Search field: `Theme.headerBackground`
- Selected row: `Theme.accent.opacity(0.15)`
- Text: `Theme.headerText`
- Disabled actions: `Theme.accentDisabled`

## Command Registry

### Protocol
```swift
protocol AppCommand: Identifiable {
    var id: String { get }
    var title: String { get }
    var icon: String { get }
    var scope: CommandScope { get }
    var isAvailable: Bool { get }
    func execute(context: CommandContext)
}

enum CommandScope { case global, cell }

struct CommandContext {
    let focusedCellID: UUID?
    let cellUIState: CellUIState?
    let store: WorkspaceStore
    let sessionManager: TerminalSessionManager
}
```

### Initial Commands

| Action | Scope | Available when |
|---|---|---|
| Toggle Notes | Cell | Always |
| Toggle File Explorer | Cell | Always |
| Set Terminal Directory | Cell | Always |
| Set Explorer Directory | Cell | Always |
| New File | Cell | Explorer visible |
| New Folder | Cell | Explorer visible |
| Show/Hide Hidden Files | Cell | Explorer visible |
| Switch Grid Layout | Global | Always |
| Toggle API Locker | Global | Always |

Toggle Git Sidebar deferred to Pack 011.

### Search
Simple substring matching — fuzzy search is overkill for ~10 items.

## Implementation Order

1. Create `CellUIState` observable, lift state from CellView
2. Add `focusedCellID` tracking to ContentView
3. Fix cell-scoped notes notification filtering
4. Create `AppCommand` protocol + `CommandRegistry`
5. Build palette UI overlay + wire actions

## Impact

- **UI impact:** Zero (hidden until invoked)
- **Architectural impact:** High — CellUIState, focusedCellID, and command registry are new patterns used by Pack 010 and Pack 011
