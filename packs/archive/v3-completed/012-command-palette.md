# Pack 012: Command Palette

**Type:** Feature Spec
**Priority:** Medium
**Competitors:** Warp, Calyx
**Codex Review:** BLOCK → fixed (4 critical findings resolved)

## Problem

As TermGrid gains features, discoverability drops. Users need to remember which icon does what.

## Solution

Global command palette triggered by `Cmd+Shift+P`. But this requires architectural prerequisites first.

### Prerequisite 1: Lift Cell UI State to Observable Model

Cell toggle states (`showNotes`, `showExplorer`, `showGit`) are currently private `@State` in CellView. The command palette (and any future external control) can't reach them.

**Fix:** Create a `CellUIState` observable class per cell, owned by ContentView (or WorkspaceStore), passed to CellView as a binding/environment. Contains:
- `showNotes: Bool`
- `showExplorer: Bool`
- `showGit: Bool` (for Pack 011)
- `showHiddenFiles: Bool`
- `isCreatingNewItem: Bool`, `newItemIsFolder: Bool`

CellView reads/writes these instead of private `@State`. The command palette mutates them directly via the focused cell's `CellUIState`.

### Prerequisite 2: Focused Cell Tracking

No centralized `focusedCellID` exists. Focus is inferred locally per cell from AppKit responder chain.

**Fix:** Add `focusedCellID: UUID?` on ContentView (or a shared observable). Update it by:
- Adding an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` or `.becomeFirstResponder` observer at the window level
- Walking the responder chain from `NSApp.keyWindow?.firstResponder` upward to find which cell's container the responder belongs to
- Updating `focusedCellID` on each responder change

This also fixes the existing broken notes focus notification (see Prerequisite 3).

### Prerequisite 3: Fix Cell-Scoped Notifications

`NotificationCenter.post(name: .focusNotesPanel, object: cell.id)` posts with cell ID, but NotesView subscriber ignores the object and reacts globally — any notes panel in any cell responds.

**Fix:** Filter on `cell.id` in the NotesView subscriber:
```swift
.onReceive(NotificationCenter.default.publisher(for: .focusNotesPanel)) { notification in
    guard let targetID = notification.object as? UUID, targetID == cellID else { return }
    // focus the text view
}
```

### UI fit:
- **Zero new buttons.** Keyboard trigger `Cmd+Shift+P`
- **Also register as macOS menu item** (`Commands` in SwiftUI `App`) for discoverability
- **Overlay:** Centered floating panel (400px wide, max 300px tall)
- **Mount point:** `.overlay` at the `Window` scene level in `TermGridApp`, NOT inside ContentView's HStack. This ensures correct z-order above everything including API locker and hover tooltips.
- **Dismisses on:** Escape, clicking outside, selecting an action
- **Context header:** Shows "Cell: {label}" or "Global" to indicate scope

### Keyboard handling:
- Use macOS `Commands` / `.keyboardShortcut` for the trigger — NOT ad hoc `NSEvent` monitors
- **Runtime verification needed:** When terminal NSView or ComposeBox NSTextView is first responder, SwiftUI scene commands may not intercept. If this fails at runtime, fall back to `NSEvent.addLocalMonitorForEvents` at the window level with explicit `Cmd+Shift+P` detection.

### Actions (initial set):
| Action | Scope | Available when | Dependency |
|---|---|---|---|
| Toggle Notes | Cell | Always | — |
| Toggle File Explorer | Cell | Always | — |
| Set Terminal Directory | Cell | Always | — |
| Set Explorer Directory | Cell | Always | — |
| New File | Cell | Explorer visible | — |
| New Folder | Cell | Explorer visible | — |
| Show/Hide Hidden Files | Cell | Explorer visible | — |
| Switch Grid Layout | Global | Always | — |
| Toggle API Locker | Global | Always | — |
| Toggle Git Sidebar | Cell | Always | Pack 011 |

**Note:** Toggle Git Sidebar is deferred until Pack 011 is implemented. Include it in the registry with `isAvailable: false` until git sidebar exists, or omit entirely and add when Pack 011 ships.

### Command Registry:
- `AppCommand` protocol: `id: String`, `title: String`, `icon: String`, `isAvailable: Bool`, `execute()`
- `CommandRegistry` class: `[AppCommand]` populated at init with global actions + cell-scoped actions (cell-scoped closures capture `focusedCellID` + `CellUIState`)
- Registry also enables future macOS menu bar integration

### Theme:
- Background: `Theme.cellBackground` with `shadow(radius: 20)`
- Search field: `Theme.headerBackground`
- Selected row: `Theme.accent.opacity(0.15)`
- Text: `Theme.headerText`
- Disabled actions: `Theme.accentDisabled`
- Search: simple substring matching (fuzzy search is overkill for 10 items)

### Implementation order:
1. Prerequisite 1: Lift cell UI state to `CellUIState` observable
2. Prerequisite 2: Add focused cell tracking
3. Prerequisite 3: Fix cell-scoped notes notification
4. Command registry + palette UI
5. Wire actions

### UI impact: Zero (hidden until invoked). Architectural impact: High (lifting cell state, focused cell tracking, command registry are new patterns that benefit future features)
