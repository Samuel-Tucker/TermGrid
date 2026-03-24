# Pack 034: Persistent Workspace Sessions

**Type:** Feature Spec
**Priority:** High
**Depends on:** Pack 020 (Workspaces), Pack 024 (Agent Detection)
**Competitors:** iTerm2 (keeps all sessions alive), tmux (sessions survive detach), Warp (persistent workspaces)
**Reviewed:** Codex gpt-5.4 xhigh multi-agent — BLOCK → all 5 critical findings addressed below

## Problem

When switching workspaces, TermGrid kills all terminal sessions in the departing workspace and spawns fresh shells on return. Scrollback bytes are saved and replayed so the terminal *looks* restored, but the underlying process is gone. This means:

1. **Long-running processes die** — `npm run dev`, `docker compose up`, training jobs, watchers — all terminated on workspace switch
2. **Agent sessions are destroyed** — Claude Code, Codex, Aider sessions in progress are killed mid-conversation
3. **Shell state is lost** — environment variables set in-session, directory stack, shell functions, aliases loaded at runtime, background jobs
4. **Users learn not to switch** — the cost of switching workspaces is too high, defeating the purpose of having workspaces

The current behavior was a pragmatic v1 decision (Pack 020), but it makes workspaces feel like disposable layouts rather than persistent project contexts.

## Solution

Keep terminal sessions alive across workspace switches. Instead of kill-on-leave / spawn-on-enter, the session manager retains all sessions in memory. Switching workspaces swaps which sessions are *displayed*, not which sessions *exist*.

### Core principle

Sessions are owned by the `TerminalSessionManager` for their full lifetime (until the cell is deleted or workspace is closed). Workspace switching changes only the **view binding**, not the session lifecycle.

### Architecture change

```
BEFORE (Pack 020):
  switchWorkspace → saveScrollback → killAll → switchStore → ensureSession (new shell)

AFTER (Pack 034):
  switchWorkspace → flushAllScrollback → detachViews → switchStore → reattachViews (same shell)
```

### Session lifecycle (revised)

| Event | Before (020) | After (034) |
|-------|-------------|-------------|
| Switch away from workspace | Kill sessions, save scrollback | Detach terminal views, sessions keep running |
| Switch back to workspace | Create new sessions, replay scrollback | Reattach terminal views to existing sessions |
| Create new workspace | Kill current sessions | Detach current sessions (keep alive) |
| Duplicate workspace | Kill current sessions | Detach current sessions (keep alive); new workspace gets fresh sessions |
| Close active workspace | Kill active sessions | Kill active sessions (unchanged) |
| Close background workspace | N/A (wasn't possible) | Kill that workspace's sessions by cell UUID enumeration |
| Delete cell | Kill session | Kill session (unchanged) |
| App quit / background | Kill all, save active scrollback | Flush scrollback for ALL workspaces, then kill all |
| App launch | Create sessions, replay scrollback | Create sessions, replay scrollback (unchanged) |

### Key design decisions

1. **Sessions keyed by cell UUID** — no change to the existing `sessions: [UUID: TerminalSession]` dictionary. Sessions for non-active workspaces simply remain in the dictionary while their views are detached.

2. **View detach/reattach** — `TerminalSession` wraps a `LoggingTerminalView` (NSView). On workspace switch, the terminal NSView is removed from its superview but not deallocated. On return, it is re-inserted into the cell's view hierarchy. The PTY continues writing to the view's buffer regardless of whether it's displayed.

3. **Scrollback flush covers all workspaces on quit** — `WorkspaceCollection.flush()` currently only flushes `activeStore`. Must be extended to iterate all workspace stores and flush scrollback for every workspace with live sessions, so background workspace output since the last switch is not lost on restart.

4. **`createSession` remains a force-recreate API** — the existing semantics (kill old → create new) are used by restart buttons, cwd changes, and command palette actions. These must not change. A new `reattachOrEnsureSession` path handles the workspace-switch case separately.

5. **Strong process-exit delegate** — SwiftTerm's `processDelegate` on `LocalProcessTerminalView` is `weak`. The current `TerminalContainerView.Coordinator` is the delegate, but it's owned by SwiftUI and released when the view leaves the hierarchy. For detached sessions, process exit would go unnoticed. The session itself must own the delegate to survive view teardown.

6. **Memory budget** — each live terminal session holds its scrollback buffer in memory (~1-4 MB typical, capped at 5000 history lines). With a 3x3 grid across 5 workspaces, that's up to 45 sessions. At 4 MB each, worst case is ~180 MB — acceptable for a desktop app on macOS.

7. **Process resource awareness** — idle shells consume minimal CPU. Background processes (servers, watchers) continue using resources as expected. This matches user intent — they started those processes to keep running.

### UI fit

- **No UI changes required** — this is a backend lifecycle change. Workspace tabs, grid layout, and cell views all remain identical.
- **Optional: activity indicator** — if a background workspace has a session producing output, show a subtle dot on the workspace tab. This is a polish item, not required for v1.

### Data model changes

None. The `Workspace`, `Cell`, `WorkspaceCollection`, and `TerminalSession` models remain unchanged. The change is in `ContentView` workspace flows, `TerminalSessionManager`, `TerminalContainerView`, and `WorkspaceCollection.flush()`.

---

## Implementation Steps

### Phase 1: Process-exit delegate ownership (fixes Codex finding #4)

**Problem:** `TerminalContainerView.Coordinator` is the `processDelegate` for SwiftTerm's `LocalProcessTerminalView`. It sets `session.isRunning = false` on process exit. But the coordinator is owned by SwiftUI — when the view leaves the hierarchy on workspace switch, SwiftUI releases the coordinator. SwiftTerm's `processDelegate` is `weak` (confirmed at `MacLocalTerminalView.swift:92`), so it becomes nil. If the process exits while detached, `isRunning` never flips to false.

**Fix:** Move process-exit handling into `TerminalSession` itself.

1. **Make `TerminalSession` conform to `LocalProcessTerminalViewDelegate`** — add the required methods directly on the session class. The critical one is `processTerminated(source:exitCode:)` which sets `isRunning = false`.

2. **Set `terminalView.processDelegate = self` in `TerminalSession.init`** — the session is retained by `TerminalSessionManager` for its full lifetime, so this is always a strong reference chain: `sessionManager → session → terminalView`, and `terminalView.processDelegate` (weak) → `session` (retained by sessionManager). The delegate survives view detach.

3. **Simplify `TerminalContainerView.Coordinator`** — remove the `LocalProcessTerminalViewDelegate` conformance. The coordinator becomes a thin shell (or is removed entirely if no other coordinator duties exist). `makeNSView` no longer sets `processDelegate` — it's already set by the session.

4. **Verify:** `processDelegate` is set once in `TerminalSession.init` and never reassigned. `TerminalContainerView.makeNSView` returns `session.terminalView` without touching the delegate.

### Phase 2: Stop killing sessions on workspace switch (fixes Codex finding #5)

**Problem:** `switchWorkspace`, `createNewWorkspace`, and `duplicateWorkspace` all contain identical kill loops. The plan must cover all three, not just `switchWorkspace`.

**Files:** `ContentView.swift:794-855`

5. **Modify `switchWorkspace(to:)`** (`ContentView.swift:794`):
   ```
   BEFORE:
     store.saveScrollback()
     for cell in store.workspace.visibleCells {
         sessionManager.killSession(for: cell.id)
         sessionManager.killSplitSession(for: cell.id)
     }
     cellUIStates.removeAll()
     focusedCellID = nil
     collection.switchToWorkspace(at: index)
     ...

   AFTER:
     cellUIStates.removeAll()
     focusedCellID = nil
     collection.switchToWorkspace(at: index)
     collection.activeStore.sessionManager = sessionManager
     collection.activeStore.cellUIStates = cellUIStates
   ```
   - Remove the kill loop entirely
   - Remove `store.saveScrollback()` — no longer needed per-switch (app-quit flush handles persistence)
   - Keep `cellUIStates.removeAll()` and `focusedCellID = nil`

6. **Modify `createNewWorkspace()`** (`ContentView.swift:813`):
   - Remove the kill loop (same change as above)
   - Remove `store.saveScrollback()`
   - Keep UI state cleanup and `collection.createWorkspace()` call

7. **Modify `duplicateWorkspace(at:)`** (`ContentView.swift:844`):
   - Remove the kill loop
   - Remove `store.saveScrollback()`
   - Duplicate creates new cell UUIDs, so new sessions will be created by `ensureSession`. Original workspace's sessions stay alive.

### Phase 3: Reattach existing sessions instead of creating new ones (fixes Codex finding #3)

**Problem:** `ensureSession(for:)` currently guards on `sessionManager.session(for: cell.id) == nil`. This already skips creation if a session exists. But the guard must be extended to also check split sessions and handle the "session exists but process exited" case.

**File:** `ContentView.swift:758`

8. **Modify `ensureSession(for:)`**:
   ```swift
   private func ensureSession(for cell: Cell) {
       if let existing = sessionManager.session(for: cell.id) {
           // Session survived from previous workspace visit
           // Restore explorer state if needed
           if cell.showExplorer {
               uiState(for: cell.id).bodyMode = .explorer
           }
           // Terminal view is reattached automatically by NSViewRepresentable
           // when SwiftUI re-renders the cell
           return
       }

       // No existing session — create fresh (first visit or after workspace close)
       // ... existing creation code unchanged ...
   }
   ```
   - If session exists (running or exited), skip creation. The NSViewRepresentable will hand back `session.terminalView` via `makeNSView`, reconnecting the view.
   - If session is exited (`isRunning == false`), user sees the exited state. They can manually restart via the existing restart button. No auto-restart.
   - `createSession` / `createSplitSession` semantics are **unchanged** — they remain force-recreate APIs. Only the `ensureSession` call path changes.

   **Note:** `ensureSession` uses the public API `sessionManager.session(for:)` (not the private `sessions` dictionary).

### Phase 4: Close workspace must kill by cell enumeration (fixes Codex finding #1)

**Problem:** `closeWorkspace(at:)` only kills sessions when `wasActive`. For background workspaces with persistent sessions, the PTYs would leak.

**File:** `ContentView.swift:826`

9. **Modify `closeWorkspace(at:)`**:
   ```swift
   private func closeWorkspace(at index: Int) {
       guard collection.workspaces.count > 1 else { return }
       let wasActive = index == collection.activeIndex

       // Kill ALL sessions for the workspace being closed,
       // whether active or background
       let workspace = collection.workspaces[index]
       for cell in workspace.cells {
           sessionManager.killSession(for: cell.id)
       }
       // Also clean up scrollback files
       for cell in workspace.cells {
           scrollbackManager.removeRaw(cellID: cell.id, sessionType: .primary)
           scrollbackManager.removeRaw(cellID: cell.id, sessionType: .split)
       }

       if wasActive {
           cellUIStates.removeAll()
           focusedCellID = nil
       }
       collection.closeWorkspace(at: index)
       if wasActive {
           collection.activeStore.sessionManager = sessionManager
           collection.activeStore.cellUIStates = cellUIStates
       }
   }
   ```
   - Enumerate `workspace.cells` (all cells, not just `visibleCells`) to catch hidden cells in grids smaller than the cell array
   - Kill sessions for background workspaces too
   - `killSession` already handles both primary and split sessions

### Phase 5: Flush all workspaces on app quit (fixes Codex finding #2)

**Problem:** `WorkspaceCollection.flush()` only calls `activeStore.saveScrollback()`. Background workspace sessions produce output after the last switch, but that output is never persisted. On app restart, it's lost.

**File:** `WorkspaceCollection.swift:149`

10. **Modify `WorkspaceCollection.flush()`**:
    ```swift
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        // Flush scrollback for ALL workspaces, not just active
        if let sessionManager = activeStore.sessionManager {
            for workspace in workspaces {
                for cell in workspace.cells {
                    if let session = sessionManager.session(for: cell.id) {
                        scrollbackManager.saveRaw(
                            cellID: cell.id, sessionType: .primary,
                            data: session.getRawScrollback()
                        )
                    }
                    if let splitSession = sessionManager.splitSession(for: cell.id) {
                        scrollbackManager.saveRaw(
                            cellID: cell.id, sessionType: .split,
                            data: splitSession.getRawScrollback()
                        )
                    }
                }
            }
        }
        persistCollection()
    }
    ```
    - This requires `flush()` to have access to `sessionManager` and `scrollbackManager`. Currently `flush()` delegates to `activeStore.saveScrollback()`. Either pass them as parameters or store a reference on `WorkspaceCollection`.
    - Alternative: add a `flushAllScrollback(sessionManager:scrollbackManager:)` method and call it from the `scenePhase` handler in `TermGridApp.swift`.

11. **Also flush on `NSApplication.willTerminate`** — `scenePhase` may not fire reliably on force-quit. Add a `NotificationCenter` observer for `NSApplication.willTerminateNotification` in `TermGridApp` that calls the same all-workspace flush.

### Phase 6: NSViewRepresentable lifecycle verification

12. **Verify `makeNSView` vs `updateNSView` behavior**:
    - `TerminalContainerView.makeNSView` returns `session.terminalView` — the same `LoggingTerminalView` instance from the session.
    - When SwiftUI re-renders a cell after workspace switch, it creates a new `TerminalContainerView` struct but calls `makeNSView`, which returns the existing NSView instance from the session. This is correct — the NSView is reused, not duplicated.
    - **Key invariant:** The parent view must use `.id(session.sessionID)` on the `TerminalContainerView` so SwiftUI tracks identity correctly. If the session is the same (same `sessionID`), SwiftUI should call `updateNSView` rather than `makeNSView`. **Verify this.** If SwiftUI always calls `makeNSView` on workspace switch (because the entire cell tree is recreated), it still works because `makeNSView` returns the existing view — but verify no double-insertion or assertion fires.

13. **Call `needsDisplay = true` after reattach**:
    - After workspace switch, when `makeNSView` or `updateNSView` fires, call `session.terminalView.needsDisplay = true` to force a redraw. SwiftTerm may have accumulated output while detached and needs to paint.

### Phase 7: Grid resize correctness

14. **Grid resize does not remove cells** — shrinking the grid hides excess cells (`visibleCells` is a computed property based on grid dimensions), but the `cells` array retains them. Sessions for hidden cells should stay alive (consistent with persistent sessions). Sessions are only killed when a cell is explicitly deleted. No code change needed here — just don't add "kill hidden cells" logic.

---

## Edge Cases

| Case | Handling |
|------|----------|
| Process exits while workspace is in background | `TerminalSession` (now the `processDelegate`) sets `isRunning = false`. On return, user sees the exited state. No auto-restart. |
| User closes background workspace | Enumerate `workspace.cells`, kill all sessions, clean up scrollback files. |
| User closes active workspace | Kill active sessions (unchanged), switch to adjacent workspace. |
| App quit / background | `flush()` iterates all workspaces and saves scrollback for every live session. Then `killAll()`. |
| Force quit (SIGKILL) | Scrollback from last `flush()` or last workspace switch is recovered. Output since then is lost (unavoidable). |
| Rapid workspace switching | No kill/create overhead — instant view detach/reattach. |
| Duplicate workspace | Original workspace sessions stay alive. New workspace gets fresh sessions via `ensureSession`. |
| Grid resize (shrink) | Hidden cells keep sessions alive. They're still accessible if grid is enlarged again. |
| Grid resize (expand) | New cells get sessions via `ensureSession`. |
| Scrollback grows large while offscreen | Bounded by SwiftTerm's 5000-line history limit. No additional cap needed. |
| `createSession` called by restart button | Force-recreate semantics unchanged. Kills old session, creates new. Works on any workspace. |
| `createSession` called by cwd change | Same — force-recreate. Not affected by persistent session changes. |

## Risks

1. **SwiftTerm NSView reuse** — the biggest unknown. `makeNSView` returns `session.terminalView` which should be the same instance. But if SwiftUI's `NSViewRepresentable` lifecycle doesn't reattach correctly (e.g., assertion on re-insertion), we need to handle it. Mitigation: test this first in isolation before wiring up the full flow.

2. **Memory growth** — 45 concurrent sessions is a lot. Monitor RSS in a real workflow with 3-4 workspaces active. If problematic, add the memory-pressure eviction path (v2).

3. **Terminal rendering glitch on reattach** — SwiftTerm may need `needsDisplay = true` or `terminal.refresh()` after being re-inserted. Handle in `makeNSView`/`updateNSView`.

4. **`processDelegate` reassignment** — if `TerminalContainerView.makeNSView` previously set `processDelegate = coordinator`, and we move it to `TerminalSession.init`, ensure no code path sets it back to the coordinator. Remove the line from `makeNSView`.

5. **`flush()` performance** — iterating all workspaces and calling `getRawScrollback()` for every session on every `scenePhase` change could be slow with many sessions. Mitigate by only flushing sessions that have produced output since last flush (track a dirty flag on `TerminalSession`).

## Testing

### Unit tests
- Create session → verify `isRunning` is true → kill → verify `isRunning` is false (existing test, confirm still passes)
- Create session → simulate process exit → verify `isRunning` flips to false via session's own delegate (not coordinator)
- `killSession` still works for workspace close and cell deletion
- `createSession` with existing running session still kills old and creates new (force-recreate preserved)
- `ensureSession` with existing session returns early without creating

### Integration tests
- Switch workspace → verify session count doesn't decrease
- Switch workspace → switch back → verify same `sessionID` is returned
- Close background workspace → verify sessions for those cells are killed
- `flush()` saves scrollback for all workspaces, not just active

### Manual tests
- Start `ping localhost` in workspace 1, switch to workspace 2, wait 10s, switch back — verify ping output continued accumulating
- Start Claude Code session in workspace 1, switch to workspace 2, switch back — verify agent session is intact and responsive
- Create new workspace (via + tab) — verify previous workspace sessions survive
- Duplicate workspace — verify original sessions survive, duplicate gets fresh sessions
- Close background workspace — verify no orphaned processes (`ps aux | grep zsh`)
- Quit app, relaunch — verify all workspace scrollback is restored (not just active)
- Open 5 workspaces with 3x3 grids (45 sessions), monitor memory usage — should stay under 300 MB total
