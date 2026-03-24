# Pack 031: Per-Terminal Close Button in Split Panes

**Type:** Feature Spec
**Priority:** High (UX confusion)

## Problem

When a cell has a split terminal (e.g. Codex left, Claude right), the only close button (amber X in header) closes the ENTIRE panel. Users can't close just one terminal in the split. The red square close buttons visible on each terminal's label bar are not functional close buttons — they're just visual artifacts. Users don't know which terminal they're closing.

## Solution

Two-level close system:

### Level 1 — Header X (existing): Close entire panel
- Keeps current behavior: amber `xmark.circle.fill` in header bar
- Confirmation: "Close this panel? All terminals will be terminated."
- Closes both primary + split terminals, removes cell from grid

### Level 2 — Per-terminal X (new): Close individual terminal in split
- Small X button on each terminal's label bar (top-right of each pane)
- Only visible when a split is active (no point showing it for single terminal)
- Confirmation: "Close [terminal label/agent name]?" with the specific terminal identified
- Closing a split terminal: kills that session, removes the split, cell becomes single-pane
- Closing the primary terminal: kills primary, promotes split to primary

### UI Design
- Per-terminal close: small `xmark` icon (9pt) at the trailing edge of TerminalLabelBar
- Color: `Theme.headerIcon` default, `Theme.error` on hover
- Only appears on hover of the label bar (keeps UI clean)
- Tooltip: "Close this terminal"

### Confirmation dialog
- Uses `.alert` with the terminal's label or detected agent name
- e.g. "Close 'Codex' terminal?" or "Close 'Claude Code' terminal?"
- If no label/agent: "Close this terminal?"
- Two buttons: "Close" (destructive) and "Cancel"

### Behavior on close
- **Close split terminal:** `sessionManager.killSplitSession(for: cellID)` — cell reverts to single pane
- **Close primary when split exists:** kill primary, promote split to primary via `sessionManager.promoteSplitToPrimary(for: cellID)`
- **Close only terminal (no split):** same as header X — close entire panel

## Files to Modify

| File | Change |
|------|--------|
| `Views/CellView.swift` | Add close button to `TerminalLabelBar` area, wire confirmation |
| `Terminal/TerminalSessionManager.swift` | Add `promoteSplitToPrimary(for:)` method |
| `Models/WorkspaceStore.swift` | Update split direction persistence on close |

## Edge Cases
- Single terminal (no split): per-terminal X hidden
- Both terminals closed: should not happen — closing last one closes the panel
- Session already ended: close button should still work (removes the dead pane)
