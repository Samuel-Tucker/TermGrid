# Pack 011: Git Sidebar

**Type:** Feature Spec
**Priority:** High
**Competitors:** Calyx

## Problem

Users working in git repos have no visibility into git status without running `git status` in the terminal.

## Solution

Add a toggleable git status panel that slides in from the left side of the cell body (opposite the notes panel).

### UI fit:
- **New header button:** `arrow.triangle.branch` icon
- **headerButtonIDs:** `["splitH", "splitV", "explorer", "git", "notes"]` (5 total)
- **Panel position:** Left side of cell body, 160px wide (same as notes — not 180px)
- **On compact cells (< 400px wide): git and notes are mutually exclusive** — opening one closes the other. On wider cells, both can coexist.

### Authoritative directory:
- Use `explorerDirectory` if non-empty, else `workingDirectory`
- Run `git rev-parse --show-toplevel` first to find repo root
- **Non-repo folders:** Show "Not a git repository" message, disable quick actions
- **Detached HEAD / rebase / merge:** Show state banner at top (e.g. "REBASING 3/5")

### Panel content:
- **Branch name** at top with copy button
- **File status list** grouped by: Staged (green), Modified (amber), Untracked (gray)
- Each row: colored dot + filename (truncated)
- **No diff line counts in V1** — `git status --porcelain=v2` doesn't provide them, and running extra diffs every 2s across multiple cells is expensive
- Click a file → sets it as the file explorer preview target (requires lifting preview state out of FileExplorerView's private `@State` into shared per-cell state)
- **Quick actions:** Stage All, Unstage All

### Implementation approach:
- `GitStatusModel` — run git commands via `Process` on a **background Task**, parse on MainActor
- Poll every 3 seconds when panel is visible (not 2s — reduce load for multi-cell grids)
- `GitSidebarView` — SwiftUI view matching notes panel styling
- `showGit: Bool` state on CellView (ephemeral)

### Focus cycling:
- Update `cycleFocus()` to include git sidebar in the rotation: terminal → compose → notes → git → terminal

### Theme:
- Staged: `#75BE95` (compose green)
- Modified: `Theme.accent` (#C4A574)
- Untracked: `Theme.headerIcon` (#7A756B)
- Background: `Theme.notesBackground` (#1E1E22)

### UI impact: Low — mirrors existing notes panel pattern, adds 1 header button, mutual exclusion on small cells prevents crowding
