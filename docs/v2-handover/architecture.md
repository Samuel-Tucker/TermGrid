# V1 Codebase Architecture

Understanding the existing code before adding V2 features.

## File Map

```
Sources/TermGrid/
├── TermGridApp.swift              — @main, AppDelegate (activation policy, dock icon), Window scene
├── Theme.swift                    — Centralised colour palette, Color/NSColor hex initializers
├── Resources/
│   ├── AppIcon.png                — Dock icon (512px, loaded via Bundle.module)
│   └── Assets.xcassets/           — Full icon set (16-1024px)
├── Models/
│   ├── Workspace.swift            — Cell (Codable), GridPreset, Workspace, visibleCells
│   └── WorkspaceStore.swift       — JSON persistence, cell CRUD (label, notes, workingDir, terminalLabel, splitTerminalLabel)
├── Terminal/
│   ├── TerminalSession.swift      — SwiftTerm wrapper: PTY lifecycle, send(), kill(), isRunning
│   ├── TerminalSessionManager.swift — @Observable registry: sessions + splitSessions + splitDirections
│   └── TerminalContainerView.swift — NSViewRepresentable wrapping LocalProcessTerminalView
└── Views/
    ├── ContentView.swift          — GeometryReader grid, wires all CellView callbacks
    ├── CellView.swift             — Full cell: header + terminal body + compose + notes
    ├── ComposeBox.swift           — NSTextView wrapper, Shift+Enter=send, collapsible
    ├── TerminalLabelBar.swift     — Click-to-edit monospaced label above each terminal pane
    ├── NotesView.swift            — Markdown notes panel (MarkdownUI)
    └── GridPickerView.swift       — Toolbar grid preset picker
```

## Key Types

### TerminalSession
```swift
@MainActor
final class TerminalSession {
    let cellID: UUID
    let sessionID: UUID                    // Used as SwiftUI .id() for view recreation
    let terminalView: LocalProcessTerminalView
    var isRunning: Bool

    func send(_ text: String)              // Write to PTY — this is how replies get routed
    func kill()                            // Terminate process
}
```

**V2 impact:** `send()` is the method that notification replies will call. The notification handler needs access to the correct `TerminalSession` instance via `cellID`.

### TerminalSessionManager
```swift
@MainActor @Observable
final class TerminalSessionManager {
    private var sessions: [UUID: TerminalSession]       // Primary terminals
    private var splitSessions: [UUID: TerminalSession]  // Split terminals
    private var splitDirections: [UUID: SplitDirection]

    func session(for cellID: UUID) -> TerminalSession?
    func splitSession(for cellID: UUID) -> TerminalSession?
    // ... create, kill, etc.
}
```

**V2 impact:** The notification handler needs to look up sessions by cellID. This manager is currently `@MainActor` — notification delegate callbacks may come on arbitrary threads, so you'll need `Task { @MainActor in ... }` dispatch.

### Cell (Model)
```swift
struct Cell: Codable, Identifiable {
    let id: UUID
    var label: String              // "My Feature Work"
    var notes: String
    var workingDirectory: String   // "/Users/sam/Projects/foo"
    var terminalLabel: String      // "Opus — UI Fix"
    var splitTerminalLabel: String // "Codex — Backend"
}
```

**V2 impact:** `label` + `terminalLabel` should appear in the notification title so the user knows which agent is talking.

## Data Flow

```
User types in ComposeBox
  → ComposeBox.sendText() converts \n to \r, appends \r
  → onSend callback in CellView
  → TerminalSession.send(text)
  → LocalProcessTerminalView.send(txt:)
  → PTY stdin
```

V2 notification reply will follow the same path from `TerminalSession.send()` onward.

## Theme

All colours centralised in `Theme.swift`:
- `Theme.appBackground` — `#1A1A1E`
- `Theme.terminalBackground` — `#1F1F24` (NSColor)
- `Theme.terminalForeground` — `#D4C5B0` (NSColor)
- `Theme.accent` — `#C4A574`
- Full palette with hex initializers for both `Color` and `NSColor`

## Dependencies

```swift
// Package.swift
.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0")
.package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0")
```

V2 will add: `UserNotifications` framework (system, no package needed).

## Tests

30 tests across 6 suites:
- WorkspaceTests — Cell codable, tolerant decode, round-trip
- WorkspaceStoreTests — CRUD operations, persistence
- TerminalSessionManagerTests — Create, lookup, kill, killAll
- PersistenceManagerTests — File I/O, directory creation, corruption recovery

Run: `swift test`

## Reference Repos

- **King Conch (macOS):** `/Users/sam/Projects/King-Conch-Terminal-MacOS-V1/` — has COP parser in Swift, agent status models. Port if needed but hooks approach is preferred.
- **King Conch (Electron):** `/Users/sam/Projects/King-Conch-Terminal-V1/` — same concepts in TypeScript.
- **term-bar:** `/Users/sam/Projects/term-bar/` — compose box pattern originated here (xterm.js version).
