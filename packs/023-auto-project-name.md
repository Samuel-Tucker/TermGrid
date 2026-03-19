# Pack 023: Auto-Populate Project Name

**Type:** Feature Spec
**Priority:** Low (quick win — ~15 minutes)

## Problem

When users set a working directory via the folder picker, the cell label stays empty. Users have to manually type the project name.

## Solution

When a folder path is selected via the directory picker, auto-populate the cell label with the folder name if the label is currently empty.

### Implementation:
- In `CellView.pickWorkingDirectory()` — after `onUpdateWorkingDirectory(url.path)`, check if `cell.label.isEmpty` and if so call `onUpdateLabel(url.lastPathComponent)`
- In `CellView.pickExplorerDirectory()` — same pattern after `onUpdateExplorerDirectory(url.path)`
- `url.lastPathComponent` preserves the filesystem's capitalization (e.g., "ClawdHotel" not "clawdhotel")
- Only auto-fill if label is currently empty — never overwrite user-typed labels

### Edge cases:
- Home directory selected → label would be username. Skip auto-fill for home dir.
- Root "/" selected → skip auto-fill
- Already has a label → don't overwrite

### UI impact: Zero — invisible behavior change
