# Pack 010: Session Save & Restore — Design Spec

**Date:** 2026-03-17
**Status:** Approved
**Source:** packs/010-session-save-restore.md (Codex-reviewed, blind spots fixed)

## Problem

When TermGrid quits, all terminal state is lost — scrollback, split configurations, and explorer state. Users must manually reconstruct their workspace on every launch.

## Solution

Persist layout + transcript state to disk. On relaunch, replay scrollback into terminals before starting the shell. Framed honestly as layout + transcript restore, not full terminal state restore.

## What to Persist

- **Scrollback buffers:** Last 5,000 lines per session, plain text. Stored as `{cellID}-primary.txt` and `{cellID}-split.txt` under `Application Support/TermGrid/scrollback/`.
- **Split direction:** Add `splitDirection: String?` to `Cell` model (`"horizontal"` or `"vertical"`, nil = no split). Currently lives only in `TerminalSessionManager.splitDirections` (in-memory, lost on quit).
- **Explorer visibility:** Already handled — `CellUIState.showExplorer` can be persisted via a new `showExplorer: Bool` field on `Cell`.

**Not persisted:** Running processes, SSH connections, shell environment.

## Delayed PTY Start

`TerminalSession.init` currently calls `startProcess()` immediately (line 27-33 of TerminalSession.swift). Must support two-phase init:

```swift
init(cellID: UUID, workingDirectory: String, sessionType: SessionType = .primary,
     environment: [String]? = nil, startImmediately: Bool = true)
```

When `startImmediately == false`:
1. Create `LocalProcessTerminalView`, configure appearance
2. Caller feeds restored scrollback via `terminalView.feed(text:)`
3. Caller feeds separator: `"\n── restored scrollback ──\n"`
4. Caller calls new `start()` method to spawn shell

New public method:
```swift
func start() {
    guard !isRunning || !processStarted else { return }
    terminalView.startProcess(executable: shell, args: ["-l"],
                              environment: env, execName: nil,
                              currentDirectory: workingDirectory)
    processStarted = true
}
```

## Scrollback History Increase

SwiftTerm defaults to 500 rows. Must set to 5,000 after view creation:
```swift
let view = LocalProcessTerminalView(frame: .zero)
view.getTerminal().changeHistorySize(5000)  // Must happen before startProcess()
```

`LocalProcessTerminalView(frame:)` does not accept `TerminalOptions` — the terminal is created internally with defaults. Use `changeHistorySize()` on the `Terminal` object after init.

## SwiftTerm API

| Operation | API | Notes |
|-----------|-----|-------|
| Read scrollback | `terminalView.getTerminal().getBufferAsData(kind: .normal, encoding: .utf8)` | Always `.normal` — `.active` misses scrollback in alternate screen |
| Replay text | `terminalView.feed(text:)` | Writes to emulator, not PTY. Use BEFORE `startProcess()` |
| Set history size | `terminalView.getTerminal().changeHistorySize(5000)` | Default is 500, must increase |

## ScrollbackManager

New class to handle scrollback I/O:

```swift
@MainActor
final class ScrollbackManager {
    private let directory: URL  // Application Support/TermGrid/scrollback/

    func save(cellID: UUID, sessionType: SessionType, content: String) throws
    func load(cellID: UUID, sessionType: SessionType) -> String?
    func cleanup(cellID: UUID)  // Remove both primary + split files
    func cleanupAll(keeping cellIDs: Set<UUID>)  // Remove orphaned files
}
```

## Cell Model Changes

Add to `Cell` struct (Workspace.swift):
```swift
var splitDirection: String?   // "horizontal", "vertical", or nil
var showExplorer: Bool        // default false
```

Both are `Codable`. On restore, `showExplorer` syncs into `CellUIState.showExplorer`.

## Save Sequence (Checkpoint)

Triggered by `WorkspaceStore.flush()` (background/inactive/terminate):

1. For each visible cell, get primary + split sessions from `TerminalSessionManager`
2. For each session: read buffer via `terminal.getBufferAsData(kind: .normal, encoding: .utf8)`
3. Write to `scrollback/{cellID}-{primary|split}.txt`
4. Sync `cell.splitDirection` from `TerminalSessionManager.splitDirection(for:)`
5. Sync `cell.showExplorer` from `CellUIState.showExplorer`
6. Save workspace JSON (existing behavior)

## Restore Sequence

On app launch, for each visible cell in `ContentView.onAppear`:

1. Check if `cell.splitDirection` is non-nil → create split session with `startImmediately: false`
2. Create primary session with `startImmediately: false`
3. Check for scrollback file at `scrollback/{cellID}-primary.txt`
4. If found: `feed(text: scrollbackContent)` then `feed(text: "\n── restored scrollback ──\n")`
5. Call `session.start()` to begin live shell
6. Repeat for split session if present
7. If `cell.showExplorer == true`, sync into `CellUIState.showExplorer`

## Cleanup

- On cell removal (`removeCell`): delete orphaned scrollback files
- On app launch: clean up scrollback files for cells that no longer exist

## Risks & Trade-offs

- **Wrapped lines lose fidelity:** `getBufferAsData` flattens rows with newlines. Acceptable for V1.
- **Crash/force-quit loses post-checkpoint data:** Checkpoint-on-flush is best-effort. Acceptable.
- **Threading is safe:** PTY output dispatches to main queue; buffer reads on main thread are serialized.
- **`hostCurrentDirectoryUpdate` is a no-op:** Shell-driven `cd` changes not synced back. Out of scope for this pack.

## UI Impact

Zero new UI elements. Invisible on relaunch except the separator line. During restore, the existing "Starting terminal..." spinner shows briefly while scrollback is fed.

## Implementation Order

1. Add `splitDirection` and `showExplorer` to Cell model (with Codable support)
2. Create `ScrollbackManager` for scrollback I/O
3. Modify `TerminalSession` for delayed PTY start + scrollback history increase
4. Wire save sequence into `WorkspaceStore.flush()`
5. Wire restore sequence into `ContentView.onAppear`
6. Add cleanup on cell removal and app launch
