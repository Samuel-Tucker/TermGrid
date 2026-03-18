# Pack 011: Git Sidebar — Design Spec

**Date:** 2026-03-18
**Status:** Approved
**Source:** packs/011-git-sidebar.md (Codex-reviewed, blind spots fixed)
**Codex Plan Review:** BLOCK → 3 critical findings integrated

## Problem

Users working in git repos have no visibility into git status without running `git status` in the terminal.

## Solution

Toggleable git status panel on the left side of each cell (opposite notes), 160px wide. Shows branch, file status, merge/rebase state, and quick actions.

## UI

- **Header button:** `arrow.triangle.branch` icon, added to headerButtonIDs: `["splitH", "splitV", "explorer", "git", "notes"]`
- **Panel:** Left side of cell body, 160px wide, same styling as notes panel
- **Toggle:** `CellUIState.showGit` (already exists from Pack 012, ephemeral)
- **Mutual exclusion:** On cells < 400px wide, opening git closes notes and vice versa. Also enforced on resize via `.onChange` of cell width.

## GitStatusModel

`@MainActor @Observable` class, one per cell.

**Directory resolution:**
- Use `explorerDirectory` if non-empty, else `workingDirectory`
- Run `git -C <path> rev-parse --show-toplevel` to find repo root
- Non-repo folders: show "Not a git repository", disable quick actions

**Git executable:** Use `/usr/bin/git` absolute path (Xcode CLT location). GUI apps launched via Spotlight may not have git on PATH. Show "git not found" if missing.

**Polling:**
- Run `git -C <repoRoot> status --porcelain=v2 --branch` every 3 seconds when `showGit == true`
- Single in-flight guard: don't start new poll if previous hasn't returned
- Stale result rejection: each poll carries a sequence number, discard older results
- Cancel on hide (`showGit` becomes false) or cell removal
- Directory change resets: cancel current poll, restart with new path

**State detection (worktree-safe):**
- Use `git -C <path> rev-parse --git-dir` to find the actual git directory (not hardcoded `.git/`)
- Check `<gitDir>/MERGE_HEAD` → "MERGING"
- Check `<gitDir>/rebase-merge/` → "REBASING" (read `msgnum`/`end` for "REBASING 3/5")
- Check `<gitDir>/rebase-apply/` → "REBASING (apply)"
- This works correctly for worktrees and submodules where `.git` is a file, not a directory

**Parsed output:**
- Branch name (from `# branch.head` line)
- File entries grouped by: Staged, Modified, Untracked
- Each entry: status indicator + relative path

## GitSidebarView

SwiftUI view matching notes panel styling.

**Content (top to bottom):**
1. Branch name with copy button
2. State banner (MERGING/REBASING) in amber — only when applicable
3. File list grouped by status:
   - Staged: green dot (`#75BE95`)
   - Modified: amber dot (`Theme.accent`)
   - Untracked: gray dot (`Theme.headerIcon`)
   - Each row: colored dot + filename (truncated)
4. Quick actions at bottom: Stage All, Unstage All

**Quick actions:**
- Stage All: `/usr/bin/git -C <repoRoot> add -A`
- Unstage All: `/usr/bin/git -C <repoRoot> diff --cached --name-only --diff-filter=d | xargs /usr/bin/git -C <repoRoot> restore --staged --`
- On unborn branches (no HEAD): use `/usr/bin/git -C <repoRoot> rm --cached -r .`

**File click:** Sets `previewingFile` on CellView → FileExplorerView reacts and shows preview. If explorer is hidden, show explorer first.

**Background:** `Theme.notesBackground` (`#1E1E22`)

## Preview State Lifting

`FileExplorerView.previewingFile` is currently `@State private`. Must lift to CellView:

- CellView owns: `@State private var previewingFile: String? = nil`
- FileExplorerView accepts: `previewingFile: Binding<String?>`
- Git sidebar sets `previewingFile` on file click
- If explorer hidden when git file clicked: set `showExplorer = true` first, then set preview target

## Focus Cycling

Update `cycleFocus()` rotation: terminal → compose → git → notes → terminal.
- Add `.focusGitPanel` notification (cell-scoped, like `.focusNotesPanel`)
- If git sidebar hidden, skip it in the cycle

## Theme Additions

```swift
static let staged = Color(hex: "#75BE95")  // compose green, for staged files
```

State banner: amber background with white text.

## Implementation Order

1. Add `staged` color to Theme
2. Create `GitStatusModel` (git commands, parsing, polling)
3. Create `GitSidebarView` (UI)
4. Lift `previewingFile` from FileExplorerView to CellView
5. Add git header button + wire sidebar panel into CellView
6. Add mutual exclusion logic (including resize handler)
7. Update focus cycling
8. Add "Toggle Git Sidebar" to CommandRegistry
