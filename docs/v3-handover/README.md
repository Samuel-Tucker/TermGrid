# TermGrid V3 — Feature Pack Development

## What This Repo Is

TermGrid V3, forked from V2 on 2026-03-17. V2 is a stable daily-use macOS terminal grid app at `/Users/sam/Projects/TermGrid-V2`. V1 lives at `/Users/sam/Projects/TermGrid-V1`. **Do not break V2 compatibility** — V3 adds feature packs on top.

## Version History

| Version | Location | Status | What it added |
|---------|----------|--------|---------------|
| V1 | `/Users/sam/Projects/TermGrid-V1` | Stable, daily use | Core terminal grid, splits, labels, compose box, notes, theme |
| V2 | `/Users/sam/Projects/TermGrid-V2` | Stable, daily use | Inline notifications, file explorer, API locker, close terminal |
| V3 | `/Users/sam/Projects/TermGrid-V3` | Active development | Feature packs (this repo) |

## V2 Baseline (What Already Works)

- Dynamic grid layout (1x1 to 3x3, GeometryReader fills available space)
- Horizontal + vertical split per cell
- Per-terminal editable labels
- Compose box per terminal (Enter=newline, Shift+Enter=send, collapsible)
- Notes panel per cell (markdown rendering, click-to-edit)
- Working directory picker per cell
- Session restart on process termination
- Warm dark theme (centralised `Theme.swift`)
- **File explorer** — page-flip animation, grid/list view, breadcrumb nav, file preview + edit
- **API locker** — encrypted key vault with brand cards, docs manager
- **Inline notifications** — Unix socket listener, hook scripts for Claude Code + Codex CLI, macOS notification with inline reply routing to PTY
- **Close terminal** — orange X button with inline confirmation bar, grid auto-downsizing
- **Compose box Mac Mini fix** — NSTextView autoresizing
- App icon with V2 badge
- 112 tests passing across 15 suites

Run: `./scripts/build-and-install.sh` to build, install to `~/Applications/TermGrid-V2.app`, and register with Spotlight.

## V3 Goal: Feature Packs

Build the feature packs in priority order. Each pack has been reviewed by Codex multi-agent for blind spots — critical findings are already integrated into the pack specs.

## Build Order (Recommended)

### Tier 1 — High Impact, Foundational

| # | Pack | What | Why first |
|---|------|------|-----------|
| 1 | **012: Command Palette** | Cmd+Shift+P fuzzy search over all actions | **Architectural prerequisite** — introduces `CellUIState` (lifts private @State to shared observable), `focusedCellID` tracking, and command registry. These patterns are needed by almost every other pack. |
| 2 | **010: Session Save & Restore** | Persist scrollback + layout, restore on relaunch | High user impact — most requested feature. Needs delayed PTY start (two-phase init) which is a foundation for future session features. |
| 3 | **011: Git Sidebar** | Left-side git status panel with stage/unstage | High user impact. Depends on `CellUIState` from Pack 012 (for `showGit` state). Uses `previewingFile` lifting also from 012. |

### Tier 2 — High Impact, Independent

| # | Pack | What | Why |
|---|------|------|-----|
| 4 | **013: Agent Notifications** | Already built in V2 as inline notifications. This pack extends with richer UX. | Builds on existing V2 notification subsystem. |
| 5 | **014: Floating Panes** | Detach terminals into floating windows | Independent, no dependencies. |
| 6 | **015: SSH Persistence** | Save/restore SSH connections | Depends on Pack 010 (session restore infrastructure). |

### Tier 3 — Medium Impact, Can Wait

| # | Pack | What | Why |
|---|------|------|-----|
| 7 | **016: Runnable Notebooks** | Run code blocks from notes panel | Nice-to-have, independent. |
| 8 | **017: Inline Media Preview** | iTerm2/Kitty/Sixel graphics protocol | Complex, niche use case. |
| 9 | **018: External Secrets Integration** | Import keys from 1Password, AWS, etc. | Extends API locker, not urgent. |

## Critical: Build Pack 012 First

Pack 012 (Command Palette) is the architectural prerequisite for most other packs. It introduces three patterns the codebase currently lacks:

1. **`CellUIState` observable model** — lifts `showNotes`, `showExplorer`, `showGit` from private `@State` in CellView to shared observable. Required by Packs 011, 013, 014.

2. **`focusedCellID: UUID?`** — centralized focused-cell tracking via AppKit responder chain. Required by any feature that needs to know "which cell is active".

3. **Command registry** — `AppCommand` protocol + `CommandRegistry`. Enables menu bar integration, keyboard shortcuts, and future automation.

**Start here.** Build the three prerequisites first, then the palette UI.

## Inline Notification Status

The V2 notification system is functional but needs one fix before it's fully usable:

**Issue:** Notification banners appear but the inline reply text field doesn't work — tapping "Reply" in the banner doesn't show the text input. This is likely because:
- The app needs to be properly signed (not just ad-hoc) for `UNTextInputNotificationAction` to work fully
- Or the `UNUserNotificationCenterDelegate` needs to handle the action in a specific way

**Next step:** Test with a Developer ID signed build. If that doesn't fix it, investigate `UNTextInputNotificationAction` configuration.

## File Map

```
Sources/TermGrid/
├── APILocker/                    — API key vault, cards, docs
├── Models/
│   ├── FileExplorerModel.swift   — File browser model
│   ├── PersistenceManager.swift  — JSON file I/O
│   ├── Workspace.swift           — Cell, GridPreset, Workspace
│   └── WorkspaceStore.swift      — CRUD + persistence + removeCell/compactGrid
├── Notifications/
│   ├── AgentSignal.swift         — SocketPayload, AgentSignal, enums
│   ├── HookInstaller.swift       — Hook script deployment + agent config
│   ├── MessageParser.swift       — Extract summary from agent messages
│   ├── NotificationManager.swift — macOS notification lifecycle + reply routing
│   └── SocketServer.swift        — Unix domain socket listener
├── Terminal/
│   ├── TerminalContainerView.swift — NSViewRepresentable for SwiftTerm
│   ├── TerminalSession.swift     — PTY lifecycle, send(), kill(), env vars
│   └── TerminalSessionManager.swift — Session registry + vault env injection
├── Views/
│   ├── CellView.swift            — Full cell: header + terminal + explorer + notes + close
│   ├── ComposeBox.swift          — NSTextView wrapper, Shift+Enter=send
│   ├── ContentView.swift         — GeometryReader grid, wires all callbacks
│   ├── FileEditorView.swift      — Inline file editing
│   ├── FileExplorerView.swift    — File browser with grid/list view
│   ├── FilePreviewView.swift     — Read-only file preview with line numbers
│   ├── GridPickerView.swift      — Toolbar grid preset picker
│   ├── NotesView.swift           — Markdown notes panel
│   └── TerminalLabelBar.swift    — Click-to-edit terminal label
├── TermGridApp.swift             — App entry, notification subsystem wiring
└── Theme.swift                   — Centralised colour palette

Tests/TermGridTests/              — 112 tests across 15 suites
packs/                            — Feature pack specs (010-018)
docs/superpowers/specs/           — Design specs
docs/superpowers/plans/           — Implementation plans
scripts/build-and-install.sh      — Build + install to ~/Applications
```

## Key Types Quick Reference

| Type | File | Purpose |
|------|------|---------|
| `Cell` | Workspace.swift | Cell model (id, label, notes, workingDir, terminalLabel, splitTerminalLabel, explorerDirectory, explorerViewMode) |
| `GridPreset` | Workspace.swift | Grid layout enum (1x1 to 3x3) |
| `WorkspaceStore` | WorkspaceStore.swift | Cell CRUD, persistence, removeCell + compactGrid |
| `TerminalSession` | TerminalSession.swift | PTY wrapper: send(), kill(), sessionType, env vars |
| `TerminalSessionManager` | TerminalSessionManager.swift | Session registry: primary + split + directions + vaultKeys |
| `SocketServer` | SocketServer.swift | Unix domain socket at ~/.termgrid/notify.sock |
| `NotificationManager` | NotificationManager.swift | UNNotification lifecycle + reply → PTY routing |
| `AgentSignal` | AgentSignal.swift | SocketPayload (wire) + AgentSignal (internal) |
| `FileExplorerModel` | FileExplorerModel.swift | File browser state + navigation |
| `APIKeyVault` | APIKeyVault.swift | Encrypted API key storage |

## SwiftTerm API Reference (for Pack 010)

| Operation | API | Notes |
|-----------|-----|-------|
| Read scrollback | `terminal.getBufferAsData(kind: .normal, encoding: .utf8)` | Always `.normal`, not `.active` |
| Replay text | `terminalView.feed(text:)` | Before `startProcess()` |
| History limit | `TerminalOptions(scrollbackRows: 5000)` | Default is 500 |
| Send to PTY | `session.send(text)` | Existing API |

## Run & Test

```bash
# Run tests
swift test

# Build and install
./scripts/build-and-install.sh

# Run from build dir (notifications disabled — use .app bundle)
swift run

# Launch installed app
open ~/Applications/TermGrid-V2.app
```

## Resume Command

Say: **"Build Pack 012 (Command Palette) — start with the CellUIState prerequisite"**
