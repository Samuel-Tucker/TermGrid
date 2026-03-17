# Pack 010: Session Save & Restore

**Type:** Feature Spec
**Priority:** High
**Competitors:** Wave, Zellij, WezTerm, Kitty

## Problem

When TermGrid quits, all terminal state is lost — scrollback, split configurations, and explorer state. Users must manually reconstruct their workspace on every launch.

## Solution

Persist layout + transcript state to disk and restore on launch. Frame this honestly as **layout + transcript restore**, not full terminal state restore.

### What to persist (additive to existing):
- Terminal scrollback buffer (last 5,000 lines per session, stored as plain text)
- **Separate transcripts for primary and split panes** (key: `{cellID}-primary.txt`, `{cellID}-split.txt`)
- Whether explorer was showing (`showExplorer: Bool` on Cell, default false)
- Split direction state (use `SplitDirection: Codable` enum, not `String?`)

### What NOT to persist:
- Running processes (too complex for V1)
- SSH connections (defer to Pack 015)

### Restored transcript boundary:
- Insert a visible separator line (`── restored scrollback ──`) between restored text and new live shell output so users don't confuse historical output with live state

### Storage:
- Store scrollback under `Application Support/TermGrid/scrollback/` (same root as existing persistence, NOT `~/.termgrid`)
- Checkpoint on background/inactive (same as `WorkspaceStore.flush()`)
- Clean up orphaned files when cells are removed

### Implementation risks (from Codex review):
- **Output capture is non-trivial.** `TerminalSession` and `TerminalContainerView` don't currently expose an output-capture path. Need to hook into SwiftTerm's terminal buffer to extract visible lines.
- **`hostCurrentDirectoryUpdate` is a no-op** — shell-driven `cd` changes are never synced back. Wire this up so restored cwd matches actual last directory.
- **Restore timing for splits** — `ContentView` only auto-creates primary sessions. Need a new launch path for split bootstrap + transcript replay ordering.

### UI fit:
- **Zero new UI elements.** Invisible on relaunch except the separator line.
- Reuse "Starting terminal..." pattern with "Restoring..." text during replay.
- If `showExplorer` was true, restore into explorer view (not terminal).

### UI impact: None (invisible feature)
