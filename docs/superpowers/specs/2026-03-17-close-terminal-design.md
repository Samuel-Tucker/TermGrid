# Close Terminal Feature Design

## Objective

Add an orange X close button to each terminal cell header that kills the terminal, removes the cell, and auto-downsizes the grid layout. Includes an inline confirmation bar to prevent accidental closures.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Close button position | Far right with gap separator | Visually separated from non-destructive buttons, prevents misclicks |
| Close button style | Always orange, dock-style hover | Signals destructive intent, consistent with header button pattern |
| Confirmation UX | Inline themed bar in cell | Stays in context, matches app aesthetic, no modal dialog |
| Cell removal behavior | Cell fully removed (session, label, notes, data) | Clean removal, remaining cells shift to fill gap |
| Split handling | Closing cell kills both panes | Split toggle already handles removing one pane |
| Grid downsizing | Smallest preset that fits remaining cells | Never hides a running terminal |
| Remaining terminals | Keep running, reorganize into smaller grid | No disruption to running sessions |

## Close Button

Orange X icon in the cell header, separated from other dock-style buttons by ~8px spacer.

- Icon: `xmark.circle.fill`
- Resting color: `Theme.accent` (warm gold/orange)
- Hover: scales up like other header buttons, tooltip "Close terminal"
- Added to `headerButtonIDs` as `"close"` for neighbor-magnification
- Always orange (not just on hover) to signal destructive action

Header layout becomes: `[Label] [repo pill] [Spacer] [splitH] [splitV] [explorer] [notes] [8px gap] [X]`

## Confirmation Bar

When X is clicked, a bar slides down from the header into the cell body area.

- Background: `Theme.headerBackground` with 4px `Theme.accent` left border stripe
- Text: "Close this terminal?" in `Theme.headerText`, size 12
- Buttons: "Cancel" (plain, `Theme.headerIcon`) and "Close" (orange accent, semibold)
- Animation: `.transition(.move(edge: .top).combined(with: .opacity))`
- Cancel dismisses the bar, Close triggers cell removal

If the cell has a split, both terminals are killed. The entire cell is removed.

## Cell Removal Flow

1. User confirms close → `onCloseCell` callback fires from CellView to ContentView
2. ContentView calls `sessionManager.killSession(for: cellID)` — kills primary + split
3. `WorkspaceStore.removeCell(id:)` removes cell from `workspace.cells` array
4. Remaining cells shift to fill gap (natural array removal)
5. `compactGrid()` auto-adjusts grid preset

## Grid Downsizing Algorithm

Find the smallest `GridPreset` whose `cellCount` >= remaining cell count:

| Remaining cells | Preset | Slots |
|-----------------|--------|-------|
| 6+ | 3x3 | 9 |
| 5 | 3x2 | 6 |
| 4 | 2x2 | 4 |
| 3 | 2x2 | 4 (one empty) |
| 2 | 2x1 | 2 |
| 1 | 1x1 | 1 |
| 0 | 1x1 | 1 (empty) |

Empty slots render as blank space — the grid already handles `index < cells.count` checks.

## Files Modified

- `CellView.swift` — add orange X close button with gap, confirmation bar state + view, `onCloseCell` callback
- `ContentView.swift` — wire `onCloseCell` to kill session + remove cell
- `WorkspaceStore.swift` — add `removeCell(id:)` and private `compactGrid()`

No new files.

## Testing

**WorkspaceStoreTests (new tests):**
- `removeCellRemovesFromArray` — cell gone after removal
- `removeCellCompactsGrid2x2To2x1` — 4 cells, remove 2 → 2x1
- `removeCellCompactsGrid2x2To1x1` — 4 cells, remove 3 → 1x1
- `removeCellStaysAt2x2With3Cells` — 4 cells, remove 1 → stays 2x2
- `removeCellFrom3x3` — 9 cells, remove to 5 → 3x2
- `removeLastCellLeavesEmpty1x1` — edge case

## Constraints / Non-Goals

- Do NOT add "undo close" — keep it simple
- Do NOT add close confirmation preference (always confirm)
- Do NOT allow closing individual split panes via this button (use split toggle for that)
