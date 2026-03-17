# Pack 014: Floating Panes

**Type:** Feature Spec
**Priority:** Low
**Competitors:** Zellij

## Problem

Sometimes users need a quick terminal for a one-off command without disrupting their grid layout.

## Solution

A floating terminal pane that overlays the grid area. Think Picture-in-Picture for terminals.

### V1 scope (narrowed per Codex feedback):
- **Fixed size** (350x250) — no resize in V1. Resize adds complexity with SwiftTerm mouse event handling.
- **Title-bar draggable only** — drag gesture restricted to a 24px title bar, not the terminal body. This prevents conflicts with SwiftTerm's mouse event handling.
- **Anchored to grid region** — `.overlay` on `gridContent`, not the full `ContentView`. This prevents covering the API locker sidebar.
- **Max 1 at a time.**

### UI fit:
- **Trigger:** `Cmd+Shift+F` via macOS `Commands` (not local event monitor)
- **No toolbar button in V1** — keep it keyboard-only to avoid adding chrome for a lightweight feature
- **Position:** Bottom-right of grid area, draggable within grid bounds
- **Contains:** Terminal + compose box. No header icons, no notes, no splits.
- **Dismiss:** Click X on title bar, or `Cmd+Shift+F` again

### Session model:
- Extend `TerminalSessionManager` with a `floatingSession` concept (not tied to any `cellID`)
- Working directory: home directory (not "focused cell" — there's no focused cell model yet, per Codex feedback)
- Vault env vars injected same as grid cells

### Focus:
- Floating pane does NOT participate in `Ctrl+Tab` cell focus cycling
- Click into it to focus, click a grid cell to return focus there
- Escape dismisses if compose is empty

### Styling:
- Background: `Theme.cellBackground`
- Border: `Theme.accent` (1px) — distinguishes from grid cells
- Corner radius: 12px
- Shadow: `shadow(radius: 12)`
- Title bar: `Theme.headerBackground` with "Quick Terminal" label + X button

### UI impact: Low — hidden until invoked, floats above grid only (not API locker)
