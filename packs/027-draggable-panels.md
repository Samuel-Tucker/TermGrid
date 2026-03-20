# Pack 027: Draggable Panel Rearrangement

**Type:** Feature Spec
**Priority:** High
**Competitors:** iTerm2 pane drag, tmux swap-pane, Warp drag-to-reorder

## Problem

Terminal panels are locked to their grid position. Users frequently want to rearrange panels — e.g. move the agent terminal next to the output terminal, or swap two panels that ended up in the wrong position. Currently the only option is to manually reconfigure each cell.

## Solution

Drag-and-drop panel rearrangement within the grid. Long-press or grab a drag handle on a panel header to pick it up, drag it over another panel to swap positions.

### UI fit:
- **Drag handle:** Grip icon (line.3.horizontal) on the left side of each cell's label bar
- **Drag preview:** Semi-transparent snapshot of the cell at 80% scale, follows cursor
- **Drop target:** Highlight target cell with `Theme.accent` border (2px) and subtle scale-up (1.02x)
- **Swap animation:** Both cells animate to new positions (easeInOut 0.25s)
- **No cross-workspace drag** — panels stay within their workspace

### Data model:
- Reorder `workspace.cells` array on drop — swap indices of dragged and target cells
- Terminal sessions stay attached to their cell ID (session follows the cell, not the grid position)
- Scrollback, notes, labels all travel with the cell

### Interaction:
- **macOS:** `onDrag` / `onDrop` modifiers on CellView, or `draggable`/`dropDestination` (iOS 16+ / macOS 13+)
- **Drag threshold:** 8pt movement before drag engages (prevent accidental drags from clicks)
- **Cancel:** Drop outside grid or press Escape → animate back to original position
- **Accessibility:** Command palette action "Swap Panels" with cell selector for keyboard-only users

### Risks:
- SwiftTerm's `NSView`-backed terminal may conflict with SwiftUI drag gestures — may need NSView hit-test exclusion for terminal area, drag only from header bar
- During drag, terminal input must be suppressed to prevent accidental keystrokes
- Grid resize during drag (if window resizes) — cancel drag on layout change
