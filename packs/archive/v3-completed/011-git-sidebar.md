# Pack 011: Git Sidebar

**Type:** Feature Spec
**Priority:** High
**Competitors:** Calyx
**Codex Review:** BLOCK → fixed (5 critical findings resolved)

## Problem

Users working in git repos have no visibility into git status without running `git status` in the terminal.

## Solution

Add a toggleable git status panel that slides in from the left side of the cell body (opposite the notes panel).

### UI fit:
- **New header button:** `arrow.triangle.branch` icon
- **headerButtonIDs:** `["splitH", "splitV", "explorer", "git", "notes"]` (5 total)
- **Panel position:** Left side of cell body, 160px wide (same as notes — not 180px)
- **Mutual exclusion on narrow cells (<400px wide):** Opening git closes notes and vice versa. Enforced in CellView where `showGit`/`showNotes` state lives — toggling one explicitly sets the other to false when cell width < 400px. Use `GeometryReader` or pass cell width from ContentView.

### Authoritative directory:
- Use `explorerDirectory` if non-empty, else `workingDirectory`
- Run `git rev-parse --show-toplevel` first to find repo root
- **All git commands must use `git -C <repoRoot>`** to anchor to repo root, not working directory
- **Non-repo folders:** Show "Not a git repository" message, disable quick actions

### State banner (rebase/merge/detached):
- `git status --porcelain=v2 --branch` provides branch name and detached HEAD state (via `# branch.head (detached)`)
- For merge/rebase state, additionally check for these files/dirs in `.git/`:
  - `.git/MERGE_HEAD` → "MERGING"
  - `.git/rebase-merge/` → "REBASING" (read `msgnum`/`end` for progress "REBASING 3/5")
  - `.git/rebase-apply/` → "REBASING (apply)"
- Show state banner at top of panel with amber background

### Panel content:
- **Branch name** at top with copy button
- **File status list** grouped by: Staged (green), Modified (amber), Untracked (gray)
- Each row: colored dot + filename (truncated)
- **No diff line counts in V1** — `git status --porcelain=v2` doesn't provide them, and running extra diffs every 3s across multiple cells is expensive
- Click a file → sets it as the file explorer preview target (see preview state section below)
- **Quick actions:** Stage All, Unstage All

### Quick action safety:
- Stage All: `git -C <repoRoot> add -A`
- Unstage All: `git -C <repoRoot> diff --cached --name-only --diff-filter=d | xargs git -C <repoRoot> restore --staged --` (safe on unborn branches — avoids `git reset HEAD` which fails before first commit)
- On unborn branches (no HEAD): use `git -C <repoRoot> rm --cached -r .` for unstage all

### Preview state lifting:
- `FileExplorerView.previewingFile` is currently private `@State`. Must be lifted to shared per-cell state.
- Add `previewingFile: Binding<String?>` parameter to `FileExplorerView` (replaces private @State)
- CellView owns the state: `@State private var previewingFile: String? = nil`
- Git sidebar sets `previewingFile` on file click → FileExplorerView reacts and shows preview
- If explorer is hidden when git file is clicked, show explorer first then set preview target

### Polling lifecycle:
- `GitStatusModel` runs `git status --porcelain=v2 --branch` via `Process` on a background `Task`
- Poll every 3 seconds when panel is visible
- **Single in-flight guard:** Don't start a new poll if the previous one hasn't returned
- **Cancel on hide/close:** When `showGit` becomes false or cell is removed, cancel the polling Task
- **Stale result rejection:** Each poll carries a sequence number. If result arrives for an older sequence than current, discard it
- **Directory change resets:** When `explorerDirectory` or `workingDirectory` changes, cancel current poll and restart with new path

### Focus cycling:
- Update `cycleFocus()` rotation: terminal → compose → git → notes → terminal
- Git sidebar focus needs cell-scoped notification (like notes, but fix the existing `NotificationCenter.post` approach to be cell-scoped — pass `cell.id` as object and filter on receive)
- If git sidebar is hidden, skip it in the cycle (existing pattern for notes)

### Implementation approach:
- `GitStatusModel` — `@MainActor @Observable` class. Run git commands via `Process` on a background Task, parse on MainActor
- `GitSidebarView` — SwiftUI view matching notes panel styling
- `showGit: Bool` state on CellView (ephemeral, not persisted)

### Theme:
- Staged: `#75BE95` (compose green)
- Modified: `Theme.accent` (#C4A574)
- Untracked: `Theme.headerIcon` (#7A756B)
- Background: `Theme.notesBackground` (#1E1E22)
- State banner: amber background with white text

### Assumptions:
- App remains unsandboxed (Process calls to git would break under App Sandbox)
- `git` CLI is installed on target machines (Xcode CLT). Show "git not found" message if missing
- `previewingFile` click from git sidebar opens explorer if hidden, then navigates to preview

### UI impact: Low — mirrors existing notes panel pattern, adds 1 header button, mutual exclusion on small cells prevents crowding
