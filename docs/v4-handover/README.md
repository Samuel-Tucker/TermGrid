# TermGrid V4 — Handover Notes

## What This Repo Is

TermGrid V4, forked from V3 on 2026-03-18. V3 is the stable daily-use version at `/Users/sam/Projects/TermGrid-V3` (pushed to GitHub `Samuel-Tucker/TermGrid` branch `v3`).

## Version History

| Version | Location | Status | What it added |
|---------|----------|--------|---------------|
| V1 | `/Users/sam/Projects/TermGrid-V1` | Stable, don't touch | Core terminal grid |
| V2 | `/Users/sam/Projects/TermGrid-V2` | Legacy | File explorer, API locker, notifications |
| V3 | `/Users/sam/Projects/TermGrid-V3` | **Stable, daily use** | Command palette, session restore, git sidebar, floating panes, agent notifications, hover focus, scroll cycling |
| V4 | `/Users/sam/Projects/TermGrid-V4` | **Active development** | This repo |

## V3 Baseline (What Already Works — 151 tests, 21 suites)

Everything from V2 plus:
- **Command Palette** (Cmd+Shift+P) — fuzzy search over all actions, CellUIState observable, focusedCellID tracking
- **Session Save & Restore** — raw PTY byte capture via LoggingTerminalView, replay on launch, ScrollbackManager
- **Git Sidebar** — left-side panel with branch, staged/modified/untracked files, stage/unstage all, worktree-safe
- **Floating Panes** — Cmd+Shift+F quick terminal, resize grip, drop-into-grid, toolbar button
- **Agent Notifications** — OutputPatternMatcher scans for build/test/error patterns, notification dot + border pulse, agent shutter overlay
- **Mouse Hover Focus** — dim non-hovered cells with themed overlay
- **Cmd+Scroll Cycling** — Cmd+scroll wheel cycles through cells, momentum filtered, debounced

## V4 Build Order (Recommended)

### Tier 1 — High Impact

| # | Pack | What | Why first |
|---|------|------|-----------|
| 1 | **023: Auto-Populate Project Name** | Auto-fill cell label from folder picker | Quick win (~15 min), immediate UX improvement |
| 2 | **024: Smart Agent Detection** | Branded agent badges in terminal label bar | Builds on existing hook system, visual polish |
| 3 | **020: Workspaces** | Tab-based workspace switching | Major feature, restructures data model |

### Tier 2 — Medium Impact

| # | Pack | What |
|---|------|------|
| 4 | **022: Pop Out Compose Box** | Floating compose overlay for long prompts |
| 5 | **021: Skills Storage** | Snippet/prompt manager panel |

### Tier 3 — Carried from V3

| # | Pack | What |
|---|------|------|
| 6 | **015: SSH Persistence** | Save/restore SSH connections (depends on Pack 010) |
| 7 | **016: Runnable Notebooks** | Run code blocks from notes panel |
| 8 | **017: Inline Media Preview** | iTerm2/Kitty/Sixel graphics |
| 9 | **018: External Secrets Integration** | Import from 1Password, AWS |

## Key Architecture (inherited from V3)

### State Management
- **@Observable classes:** WorkspaceStore, TerminalSessionManager, FileExplorerModel, APIKeyVault, DocsManager, GitStatusModel, CellNotificationState
- **CellUIState:** Per-cell observable with showNotes, showExplorer, showGit, shutterEnabled. Owned by ContentView in `[UUID: CellUIState]` dict.
- **focusedCellID:** Tracks which cell has keyboard focus via NSEvent monitor

### Terminal Architecture
- **LoggingTerminalView:** Subclass of SwiftTerm's LocalProcessTerminalView. Captures raw PTY bytes for scrollback restore + scans for notification patterns.
- **TerminalSession:** Wraps LoggingTerminalView with delayed start support, scrollback replay, pattern match callback.
- **TerminalSessionManager:** Session registry with primary/split/floating sessions, notification states.

### Notification System
- **Hook scripts:** `~/.termgrid/hooks/` — Claude Code (Start/Stop/Notification events) and Codex (completion events)
- **SocketServer:** Unix domain socket at `~/.termgrid/notify.sock`
- **AgentSignal:** Parsed from SocketPayload with cellID, agentType, eventType (started/complete/needsInput)
- **OutputPatternMatcher:** Line-buffered, ANSI-stripped regex matching in dataReceived

### Key File Paths
- `Sources/TermGrid/TermGridApp.swift` — App entry, notification subsystem, Commands menu
- `Sources/TermGrid/Views/ContentView.swift` — Grid layout, command palette, floating pane, hover/scroll
- `Sources/TermGrid/Views/CellView.swift` — Cell UI, header buttons, git sidebar, agent shutter
- `Sources/TermGrid/Terminal/TerminalSession.swift` — PTY lifecycle, delayed start, scrollback
- `Sources/TermGrid/Terminal/LoggingTerminalView.swift` — Raw byte capture + pattern matching
- `Sources/TermGrid/Models/WorkspaceStore.swift` — CRUD + scrollback save on flush
- `Sources/TermGrid/CommandPalette/CommandRegistry.swift` — All registered commands + notification names

## To Resume

Open V4 and say: **"Build Pack 023 (Auto-Populate Project Name) — it's a quick win, then move to Pack 024 (Smart Agent Detection)"**

## Build & Run

```bash
cd /Users/sam/Projects/TermGrid-V4
./scripts/build-and-install.sh
# Installs to ~/Applications/TermGrid-V4.app
```

## GitHub

V3 stable: `https://github.com/Samuel-Tucker/TermGrid` (branch `v3`)
V4: local only until ready to push
