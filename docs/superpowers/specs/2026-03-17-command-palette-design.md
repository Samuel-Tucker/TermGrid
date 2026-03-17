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
}
```

Note: `showHiddenFiles` already lives on `FileExplorerModel` (not CellView `@State`). `isCreatingNewItem` and `newItemIsFolder` are `@State` on `FileExplorerView`. These stay where they are — the command palette triggers "New File"/"New Folder" via a notification or callback on `FileExplorerModel`, not by lifting state.

**Ownership:** ContentView holds `[UUID: CellUIState]` dictionary. Each CellView receives its `CellUIState` instance. CellView reads/writes these instead of private `@State`.

**Why:** Command palette (and any future external control) needs to mutate cell panel states. Private `@State` is unreachable from outside the view.

### 2. Focused Cell Tracking

Add `focusedCellID: UUID?` on ContentView.

**Update mechanism:** Add an `NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown])` at the window level. On each event, walk responder chain from `NSApp.keyWindow?.firstResponder` upward to find which cell's container owns the responder. Update `focusedCellID` on each change. Using both `.leftMouseDown` and `.keyDown` ensures click-to-focus transitions are captured, not just keyboard events.

**Why:** Palette needs to know which cell to scope commands to. Also enables future features that act on the focused cell.

### 3. Fix Cell-Scoped Notifications

`NotificationCenter.post(name: .focusNotesPanel, object: cell.id)` posts correctly, but NotesView subscriber ignores the `object:` parameter — all cells react.

**Fix:** Add `let cellID: UUID` parameter to `NotesView` (currently only takes `notes: String` and `onUpdate`). Update call site in CellView to pass `cell.id`. Then filter on cell ID in receiver:
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
- Mount: `.overlay` on `Window` scene in TermGridApp.swift (app uses `Window`, not `WindowGroup`)
- Size: 400px wide, max 300px tall
- Position: Centered in window
- Dismiss: Escape, click outside, select action

### Keyboard Navigation
- Search field auto-focuses on open
- Up/Down arrow keys move selection through results
- Enter executes the selected command
- Escape dismisses the palette

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

### Types
```swift
enum CommandScope { case global, cell }

struct CommandContext {
    let focusedCellID: UUID?
    let cellUIState: CellUIState?
    let store: WorkspaceStore
    let sessionManager: TerminalSessionManager
}

struct AppCommand: Identifiable {
    let id: String
    let title: String
    let icon: String
    let scope: CommandScope
    var isAvailable: (CommandContext) -> Bool = { _ in true }
    let action: (CommandContext) -> Void
}
```

Using a struct with closures rather than a protocol — simpler for ~10 static commands, matches the pack spec's description of closures capturing `focusedCellID` + `CellUIState`.

### Data Flow
`WorkspaceStore` and `TerminalSessionManager` are `@State` on `TermGridApp` and already passed to `ContentView`. Since the palette overlay mounts at the `Window` scene level in `TermGridApp`, it has direct access to both. The `[UUID: CellUIState]` dictionary and `focusedCellID` are passed from ContentView up to the palette via a shared observable or binding.

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
