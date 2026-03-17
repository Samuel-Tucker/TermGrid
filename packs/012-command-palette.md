# Pack 012: Command Palette

**Type:** Feature Spec
**Priority:** Medium
**Competitors:** Warp, Calyx

## Problem

As TermGrid gains features, discoverability drops. Users need to remember which icon does what.

## Solution

Global command palette triggered by `Cmd+Shift+P`. But this requires an architectural prerequisite first.

### Prerequisite: Command Registry + Focused Cell Tracking

Before the palette can work, the app needs:

1. **`focusedCellID: UUID?`** tracked in `ContentView` or `WorkspaceStore` — updated whenever a cell's terminal/compose/notes becomes first responder
2. **`AppCommand` protocol** — `id`, `title`, `icon: String`, `isAvailable: Bool`, `execute()`
3. **Command registry** — `[AppCommand]` populated by both global actions (toggle API locker, switch grid) and cell-scoped actions (toggle notes, toggle explorer, etc.)

The palette is then just a search UI over this registry. The registry also enables future macOS menu bar integration.

### UI fit:
- **Zero new buttons.** Keyboard trigger `Cmd+Shift+P`
- **Also register as macOS menu item** (`Commands` in SwiftUI `App`) for discoverability
- **Overlay:** Centered floating panel (400px wide, max 300px tall)
- **Dismisses on:** Escape, clicking outside, selecting an action
- **Z-order:** Must be above everything including API locker and hover tooltips. Use `.overlay` at the `Window` scene level, not inside `ContentView`'s HStack.
- **Context header:** Shows "Cell: {label}" or "Global" to indicate scope

### Keyboard handling:
- Use macOS `Commands` / `.keyboardShortcut` for the trigger — NOT ad hoc `NSEvent` monitors. This avoids conflicts with ComposeBox, NotesView, and terminal responder chain.

### Actions:
| Action | Scope | Available when |
|---|---|---|
| Toggle Notes | Cell | Always |
| Toggle Git Sidebar | Cell | Always |
| Toggle File Explorer | Cell | Always |
| Set Terminal Directory | Cell | Always |
| Set Explorer Directory | Cell | Always |
| New File | Cell | Explorer visible |
| New Folder | Cell | Explorer visible |
| Switch Grid Layout | Global | Always |
| Toggle API Locker | Global | Always |
| Show/Hide Hidden Files | Cell | Explorer visible |

### Theme:
- Background: `Theme.cellBackground` with `shadow(radius: 20)`
- Search field: `Theme.headerBackground`
- Selected row: `Theme.accent.opacity(0.15)`
- Text: `Theme.headerText`
- Disabled actions: `Theme.accentDisabled`

### UI impact: Zero (hidden until invoked). Architectural impact: Medium (command registry is a new pattern)
