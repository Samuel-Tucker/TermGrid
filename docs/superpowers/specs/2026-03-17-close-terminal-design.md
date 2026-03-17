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
- NOT added to `headerButtonIDs` — the gap means it doesn't participate in dock-style neighbor magnification. It scales on its own hover only.
- Always orange (not just on hover) to signal destructive action

Header layout becomes: `[Label] [repo pill] [Spacer] [splitH] [splitV] [explorer] [notes] [8px gap] [X]`

## Confirmation Bar

When X is clicked, a bar is inserted into the CellView VStack between the header divider and the cell body `HStack`. It pushes the terminal content down (not an overlay).

- Background: `Theme.headerBackground` with 4px `Theme.accent` left border stripe
- Text: "Close this terminal?" in `Theme.headerText`, size 12
- Buttons: "Cancel" (plain, `Theme.headerIcon`) and "Close" (orange accent, semibold)
- Animation: wrapped in `if showCloseConfirmation` with `.transition(.move(edge: .top).combined(with: .opacity))`
- Cancel dismisses the bar, Close triggers cell removal

If the cell has a split, both terminals are killed. The entire cell is removed.

## Cell Removal Flow

1. User confirms close → `onCloseCell: () -> Void` callback fires from CellView to ContentView
2. ContentView calls `sessionManager.killSession(for: cellID)` — kills primary + split
3. `WorkspaceStore.removeCell(id:)` removes cell from `workspace.cells` array
4. Remaining cells shift to fill gap (natural array removal)
5. `compactGrid()` auto-adjusts grid preset

## Grid Downsizing Algorithm

Find the smallest `GridPreset` whose `cellCount` >= remaining cell count. When multiple presets have the same `cellCount`, prefer wider layouts (more columns).

Available presets: `1x1` (1), `2x1` (2), `1x2` (2), `2x2` (4), `3x2` (6), `2x3` (6), `3x3` (9).

| Remaining cells | Preset | Slots | Tie-break |
|-----------------|--------|-------|-----------|
| 7-9 | 3x3 | 9 | |
| 5-6 | 3x2 | 6 | Prefer 3x2 over 2x3 (wider) |
| 4 | 2x2 | 4 | |
| 3 | 2x2 | 4 (one empty) | |
| 2 | 2x1 | 2 | Prefer 2x1 over 1x2 (wider) |
| 1 | 1x1 | 1 | |
| 0 | 1x1 | 1 | Empty grid — shows blank background |

Empty slots render as blank space — the grid already handles `index < cells.count` checks. Closing the last cell leaves an empty 1x1 grid (just the app background). The user can resize the grid via the toolbar picker to create new cells.

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
