# Pack 010: Session Save & Restore

**Type:** Feature Spec
**Priority:** High
**Competitors:** Wave, Zellij, WezTerm, Kitty
**Codex Review:** BLOCK → fixed (4 critical findings resolved)

## Problem

When TermGrid quits, all terminal state is lost — scrollback, split configurations, and explorer state. Users must manually reconstruct their workspace on every launch.

## Solution

Persist layout + transcript state to disk and restore on launch. Frame this honestly as **layout + transcript restore**, not full terminal state restore.

### What to persist (additive to existing):
- Terminal scrollback buffer (last 5,000 lines per session, stored as plain text)
- **Separate transcripts for primary and split panes** (key: `{cellID}-primary.txt`, `{cellID}-split.txt`)
- Whether explorer was showing (`showExplorer: Bool` on Cell, default false)
- Split direction state (persist `SplitDirection` as Codable on `Cell`, not in-memory only)

### What NOT to persist:
- Running processes (too complex for V1)
- SSH connections (defer to Pack 015)

### Restored transcript boundary:
- Insert a visible separator line (`── restored scrollback ──`) between restored text and new live shell output so users don't confuse historical output with live state

### Storage:
- Store scrollback under `Application Support/TermGrid/scrollback/` (same root as existing persistence, NOT `~/.termgrid`)
- Checkpoint on background/inactive (same as `WorkspaceStore.flush()`)
- Clean up orphaned files when cells are removed

## SwiftTerm API (validated by Codex review)

Buffer extraction and replay are both supported:

| Operation | SwiftTerm API | Notes |
|-----------|--------------|-------|
| Read scrollback | `terminal.getBufferAsData(kind: .normal, encoding: .utf8)` | Always use `.normal` — `.active` misses scrollback when alternate screen (vim/less) is showing |
| Replay text | `terminalView.feed(text:)` | Writes directly to emulator, not PTY stdin. Use this BEFORE `startProcess()` |
| Get text range | `terminal.getText(start:end:)` | Alternative for selective extraction |
| History limit | `TerminalOptions.scrollbackRows` | Default is 500 — MUST set to 5000 |

### Critical: Delayed PTY start for restore

`TerminalSession.init` currently calls `startProcess()` immediately. For restore to work, the session must support a two-phase init:

1. Create `LocalProcessTerminalView`, configure appearance
2. If restoring: call `feed(text: restoredScrollback)` then `feed(text: separatorLine)`
3. THEN call `startProcess()` to begin the live shell

This means `TerminalSession.init` needs a `startImmediately: Bool = true` parameter. When restoring, pass `false`, replay scrollback, then call a new `start()` method.

### Critical: Scrollback history must be increased

SwiftTerm defaults to 500 lines of scrollback history. The pack requires 5,000. Set this when creating the terminal view:

```swift
let options = TerminalOptions(scrollbackRows: 5000)
// Pass to LocalProcessTerminalView init or configure after creation
```

### Critical: Persist split direction on Cell model

Split direction currently lives only in `TerminalSessionManager.splitDirections` (in-memory dict, lost on quit). Add to `Cell`:

```swift
var splitDirection: String?  // "horizontal" or "vertical", nil = no split
```

On restore, `ContentView` reads `cell.splitDirection` and calls `createSplitSession` if non-nil, BEFORE primary session `.onAppear`.

### Critical: Always capture .normal buffer

When saving scrollback, always use `kind: .normal` regardless of current screen mode. If the user was in vim (alternate screen), `.active` would capture the vim UI, not the scrollback history. `.normal` always has the shell history.

## Implementation risks (from original + Codex review):

- **`hostCurrentDirectoryUpdate` is a no-op** — shell-driven `cd` changes are never synced back. Wire this up so restored cwd matches actual last directory.
- **Wrapped lines lose fidelity** — `getBufferAsData` flattens rows with newlines. Wrapped lines that span multiple rows will appear as separate lines on replay. Acceptable trade-off for V1.
- **Crash/force-quit loses post-checkpoint data** — checkpoint-on-flush is best-effort. Acceptable.
- **Threading is safe** — PTY output dispatches to main queue, buffer reads on main thread are serialized. No explicit lock needed.

## Restore sequence (detailed):

1. App launches, `WorkspaceStore` loads persisted workspace (existing behavior)
2. For each visible cell in `ContentView.onAppear`:
   a. Check if `cell.splitDirection` is non-nil → create split session (with `startImmediately: false`)
   b. Create primary session (with `startImmediately: false`)
   c. Check for scrollback file at `scrollback/{cellID}-primary.txt`
   d. If found: `feed(text: scrollbackContent)` then `feed(text: "\n── restored scrollback ──\n")`
   e. Call `session.start()` to begin live shell
   f. Repeat for split session if present (`{cellID}-split.txt`)
3. If `cell.showExplorer == true`, restore into explorer view (not terminal)

## Save sequence (checkpoint):

1. On `WorkspaceStore.flush()` (background/inactive/terminate):
   a. For each cell, get primary + split sessions from `TerminalSessionManager`
   b. For each session: `terminal.getBufferAsData(kind: .normal, encoding: .utf8)`
   c. Write to `scrollback/{cellID}-{primary|split}.txt`
   d. Update `cell.splitDirection` from `TerminalSessionManager.splitDirection(for:)`
2. On cell removal (`removeCell`): delete orphaned scrollback files

### UI fit:
- **Zero new UI elements.** Invisible on relaunch except the separator line.
- Reuse "Starting terminal..." pattern with "Restoring..." text during replay.
- If `showExplorer` was true, restore into explorer view (not terminal).

### UI impact: None (invisible feature)
