# Embedded Terminals Design Spec

## Goal

Replace the "Open Terminal" placeholder in each TermGrid cell with a live embedded terminal session powered by SwiftTerm. Each cell runs a real shell in a configurable working directory, enabling multi-project terminal workflows (e.g., running Claude Code or Codex in separate project directories simultaneously).

## Architecture

Direct replacement approach: every visible cell gets a live SwiftTerm `LocalProcessTerminalView` immediately on display. `LocalProcessTerminalView` is a SwiftTerm subclass of `TerminalView` that owns both the terminal emulation and the shell process internally. Terminal sessions are managed by a runtime-only `TerminalSessionManager` that keeps sessions alive even when cells are hidden (grid resize), and reconnects them when cells become visible again. Sessions are ephemeral — they do not survive app restarts. When `environment` is `nil`, SwiftTerm's `LocalProcessTerminalView.startProcess()` constructs a curated set of environment variables via `Terminal.getEnvironmentVariables` (TERM, COLORTERM, etc.), not a full passthrough of the parent process environment. This is acceptable for our use case.

## Data Model Changes

### Cell struct

Add a `workingDirectory` field:

```swift
struct Cell: Codable, Identifiable {
    let id: UUID
    var label: String
    var notes: String
    var workingDirectory: String  // default: user's home directory
}
```

The `workingDirectory` is persisted with the workspace JSON. Default value is `FileManager.default.homeDirectoryForCurrentUser.path`.

### Custom decoding

The existing tolerant `init(from:)` on `Workspace` handles missing fields. `Cell` needs its own tolerant decoder to default `workingDirectory` when loading workspaces saved before this feature:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    label = (try? container.decode(String.self, forKey: .label)) ?? ""
    notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
    workingDirectory = (try? container.decode(String.self, forKey: .workingDirectory))
        ?? FileManager.default.homeDirectoryForCurrentUser.path
}
```

All fields use tolerant decoding (`try?` with defaults) for consistency with the `Workspace` decoder pattern.

### WorkspaceStore

Add a mutation method:

```swift
func updateWorkingDirectory(_ path: String, for cellID: UUID)
```

This updates the cell's `workingDirectory` and triggers `scheduleSave()`. The caller (CellView) is responsible for restarting the terminal session after changing the directory.

### Fix: Eliminate ephemeral cell UUIDs

**Problem:** The current `visibleCells` computed property pads with `Cell()` on every call, generating fresh UUIDs each time. With terminal sessions keyed by cell ID, these ephemeral IDs cause orphaned sessions and broken reconnection.

**Fix:** Change `setGridPreset` (which already appends cells when growing) to also persist padded cells immediately. Replace the `visibleCells` computed property so it never creates new `Cell()` instances — it only returns a prefix of the persisted `cells` array. The `init` on `Workspace` and `setGridPreset` on `WorkspaceStore` are the only places that create cells:

```swift
// Workspace.visibleCells — no more padding, just prefix
var visibleCells: [Cell] {
    Array(cells.prefix(gridLayout.cellCount))
}
```

The `Workspace.init` already creates `gridLayout.cellCount` cells, and `setGridPreset` already appends when growing. The only gap was `visibleCells` padding on-the-fly — removing that padding is the fix. If `cells.count < gridLayout.cellCount` somehow (corrupt data), the workspace loader should normalize by appending cells at load time.

The existing `Cell()` default initializer is preserved — it is still used by `Workspace.init` and `setGridPreset`.

## Terminal Session Layer

### TerminalSession

A lightweight wrapper holding the runtime state for one cell's terminal. Wraps SwiftTerm's `LocalProcessTerminalView`, which is a single object that owns both the terminal view and the shell process internally.

- **Properties:**
  - `cellID: UUID` — the cell this session belongs to
  - `sessionID: UUID` — unique per session instance (changes on restart/replacement, used for SwiftUI view identity via `.id(session.sessionID)`)
  - `terminalView: LocalProcessTerminalView` — SwiftTerm's combined view + process object
  - `isRunning: Bool` — whether the shell process is alive (set to `false` by `processDelegate.processTerminated`)

- **Lifecycle:**
  - Created with a cell ID and working directory
  - The actual SwiftTerm API is `startProcess(executable:args:environment:execName:)` — there is no `currentDirectory` parameter. To launch the shell in the cell's working directory, `TerminalSession` calls `Process.launchPath` / sets `currentDirectoryURL` on the underlying process, OR sends an initial `cd <workingDirectory>\n` command to the PTY after process start. The `cd` approach is simpler and more reliable across SwiftTerm versions.
  - Shell executable: `ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"`
  - Shell args: pass `["-l"]` to start a login shell, ensuring `.zprofile`/`.bash_profile` are sourced and the user's full PATH is available (fixes the medium risk of missing tools)
  - Destroyed when the app quits or the session is explicitly killed

### TerminalSessionManager

Manages all active sessions. Injected at app level alongside `WorkspaceStore`.

```swift
@MainActor
@Observable
final class TerminalSessionManager {
    private var sessions: [UUID: TerminalSession] = [:]

    func session(for cellID: UUID) -> TerminalSession?
    func createSession(for cellID: UUID, workingDirectory: String) -> TerminalSession
    func killSession(for cellID: UUID)
    func killAll()
}
```

- **`session(for:)`** — Returns existing session if one exists for this cell ID. Used by the view to reconnect after grid resize.
- **`createSession(for:workingDirectory:)`** — Creates a new PTY + shell process. If a session already exists for this cell, kills it first.
- **`killSession(for:)`** — Terminates a single session.
- **`killAll()`** — Called on app quit. Terminates all shell processes.

### Session lifecycle rules

| Event | Behavior |
|-------|----------|
| Cell becomes visible | Check for existing session → reconnect, or create new |
| Cell hidden (grid resize down) | Session stays alive, just not rendered |
| Cell visible again (grid resize up) | Reconnect to existing session via `.id(session.sessionID)` |
| Working directory changed | Kill existing session, create new one in new directory |
| Shell process exits (e.g., user types `exit`) | Show "Session ended" state with restart button |
| App quit | `killAll()` terminates everything |
| App launch | Fresh sessions created for all visible cells |

**Hidden session resource policy:** Hidden sessions (from grid resize) stay alive indefinitely. This is acceptable because the maximum grid is 3x3 (9 cells), so at most 8 sessions could be hidden. The resource cost of 8 idle shell processes is negligible on modern Macs. No automatic reclamation is needed.

## View Layer Changes

### TerminalContainerView (new)

`NSViewRepresentable` wrapper that hosts the `LocalProcessTerminalView` from a `TerminalSession`:

- **`makeNSView`** — Returns the session's `terminalView` (the `LocalProcessTerminalView` instance owned by the session)
- **`updateNSView`** — No-op in normal operation. Session identity changes are handled by SwiftUI view identity (see below).
- **`Coordinator`** — Sets itself as the session's `terminalView.processDelegate` (NOT `delegate` — SwiftTerm reserves `delegate` for internal use). Implements `LocalProcessTerminalViewDelegate` for:
  - `processTerminated` callback — updates `TerminalSession.isRunning` to `false`
  - Note: PTY resize is handled internally by `LocalProcessTerminalView` — no Coordinator action needed

**View identity and reconnection:** The `TerminalContainerView` is given `.id(session.sessionID)` in the parent `CellView` (NOT `cell.id`). The `sessionID` is a unique UUID that changes whenever a session is replaced (working directory change, restart after exit). This forces SwiftUI to destroy and recreate the `NSViewRepresentable`, which calls `makeNSView` with the new session's view. Using `cell.id` alone would NOT work because cell IDs are stable — SwiftUI would keep the old view when the session changes.

### CellView changes

Replace the `terminalArea` placeholder entirely:

**Before:**
```
┌─────────────────────────────────┐
│ Label Header                    │
├─────────────────────────────────┤
│                    │            │
│   [terminal icon]  │   NOTES   │
│   Open Terminal    │   ...     │
│                    │            │
└─────────────────────────────────┘
```

**After:**
```
┌─────────────────────────────────┐
│ Label Header        [📁] [📝]  │
├─────────────────────────────────┤
│                    │            │
│  $ cd ~/Projects   │   NOTES   │
│  $ claude          │   ...     │
│  ▊                 │ (toggle)  │
│                    │            │
└─────────────────────────────────┘
```

**Header additions:**
- **Folder button** (`📁`) — opens `NSOpenPanel` to pick a working directory for the cell
- **Notes toggle button** (`📝`) — shows/hides the notes side panel

**Removed from CellView:**
- `isHoveringTerminal` state
- `terminalArea` computed property
- `launchTerminal()` function
- NSCursor hover handling

**Notes panel toggle:**
- `@State private var showNotes: Bool = true`
- When hidden, `TerminalContainerView` takes the full cell width
- Toggle button in the header controls visibility

### Shell process exit state

Exit state lives on `TerminalSession` (not the view layer), because sessions can outlive their views when hidden by grid resize.

- `TerminalSession.isRunning` is set to `false` when the `processDelegate.processTerminated` callback fires
- The `TerminalContainerView` Coordinator receives the delegate callback and updates `TerminalSession.isRunning`
- `CellView` observes the session's `isRunning` state. When `false`:
  - The terminal view stays visible showing the last output
  - An overlay appears: "Session ended — [Restart]"
  - Restart button calls `sessionManager.createSession(for:workingDirectory:)` which generates a new `sessionID`, triggering SwiftUI view recreation
- If the shell exits while the cell is hidden (no active view), `isRunning` is still set to `false` via the `processDelegate`. When the cell becomes visible again, `CellView` reads `isRunning == false` and shows the "Session ended" overlay immediately.

## File Structure

### New files
- `Sources/TermGrid/Terminal/TerminalSession.swift` — Session wrapper
- `Sources/TermGrid/Terminal/TerminalSessionManager.swift` — Session registry
- `Sources/TermGrid/Terminal/TerminalContainerView.swift` — NSViewRepresentable wrapper

### Modified files
- `Package.swift` — Add SwiftTerm dependency
- `Sources/TermGrid/Models/Workspace.swift` — Add `workingDirectory` to Cell, add tolerant decoder
- `Sources/TermGrid/Models/WorkspaceStore.swift` — Add `updateWorkingDirectory` method
- `Sources/TermGrid/Views/CellView.swift` — Replace placeholder with live terminal, add header buttons
- `Sources/TermGrid/TermGridApp.swift` — Create/inject TerminalSessionManager, call `killAll()` ONLY on `NSApplication.willTerminateNotification` (NOT on `scenePhase` changes — those fire on focus loss and would kill active sessions)

## Package.swift Changes

```swift
dependencies: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0")
],
targets: [
    .executableTarget(
        name: "TermGrid",
        dependencies: [
            .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            .product(name: "SwiftTerm", package: "SwiftTerm")
        ],
        path: "Sources/TermGrid"
    ),
    // ...
]
```

## Out of Scope

- Terminal appearance customization (fonts, colors, themes)
- Custom shell selection (uses user's default shell via `$SHELL`, not configurable per-cell)
- Session persistence across app restarts
- Notes panel styling (Enter/Shift+Enter keybinding, background/font colors)
- Tab support within cells
- Split panes within cells
- Copy/paste customization (SwiftTerm handles this by default)

## Testing Strategy

- **Unit tests:** Cell tolerant decoding with/without `workingDirectory`, WorkspaceStore `updateWorkingDirectory` mutation
- **TerminalSessionManager tests:** Create session, kill session, kill all, session lookup, session replacement
- **Manual testing:** Launch app, verify shells start in correct directories, resize grid and verify sessions persist, change working directory and verify shell restarts, quit and relaunch
