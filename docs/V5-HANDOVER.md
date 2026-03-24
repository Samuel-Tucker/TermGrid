# TermGrid V5 — Handover Document

## What Is This

TermGrid is a macOS SwiftUI terminal grid application. V5 builds on the stable V4.1 codebase. The working app is at /Applications/TermGrid.app (V4.1). V5 is the development branch for new features.

This document is the playbook for any agent or developer working in V5. Read it before implementing anything.

## Architecture Overview

### Tech Stack
- macOS 14+ / SwiftUI + AppKit hybrid
- SwiftTerm (NSView-based terminal emulator)
- GRDB.swift (SQLite for autocomplete corpus)
- MarkdownUI (markdown rendering in notes)
- Swift Package Manager (swift-tools-version: 5.10)

### Key Architectural Decisions
- `@Observable` + `@MainActor` for state management (NOT Combine, NOT `@Published`)
- `CellUIState` is per-cell ephemeral state (NOT persisted in JSON)
- NEVER mutate `@State` during SwiftUI body evaluation — causes infinite re-render loops
- Terminal views are NSView-backed (SwiftTerm) — gesture/event handling conflicts with SwiftUI
- Three-way body mode: terminal | explorer | projectNotes (`CellBodyMode` enum)
- Per-pane compose state (`PaneComposeState`) for independent split terminal compose boxes
- Ghost autocomplete uses in-memory trie for sub-millisecond lookups; SQLite (GRDB) for persistence only

### Directory Structure
```
Sources/TermGrid/
  APILocker/          — API key vault + docs
  Autocomplete/       — Ghost text prediction (trigram + trie + GRDB)
  CommandPalette/     — Command registry + palette UI
  Models/             — Data layer (workspace, cell, persistence)
  Notifications/      — Agent detection, hooks, socket server
  Skills/             — Skill library storage + scanner
  Terminal/           — Session management, logging, content extraction
  Views/              — All SwiftUI views
  Resources/          — Bundled resources
  TermGridApp.swift   — App entry point
  Theme.swift         — Centralized color palette
```

### Data Storage Locations
```
~/Library/Application Support/TermGrid/
  workspaces.json    — Workspace collection (schema v2)
  autocomplete.db    — SQLite corpus + trigrams + prefixes
  skills.json        — Skill library
  api-keys.json      — API Locker vault

<repo>/.termgrid/notes/  — Project notes (per-repo)
```

### Package Dependencies
| Package | Purpose |
|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | NSView-based terminal emulator |
| [GRDB.swift](https://github.com/groue/GRDB.swift) 7.0+ | SQLite for autocomplete corpus |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) 2.0+ | Markdown rendering in project notes |

---

## Pack System

Packs are numbered feature specs in the `packs/` directory. Each pack has a problem statement, solution design, UI fit, data model changes, implementation steps, edge cases, and risks.

### How to Implement a Pack
1. Read the pack spec thoroughly — every section matters
2. Plan the implementation (use `/codex-review` for second opinion)
3. Red-team the plan before coding — check for the bugs listed in "Critical Bugs Fixed" below
4. Implement incrementally — build + test after each step
5. Run `swift test` — all 306+ tests must pass
6. If building .app: `swift build -c release && cp .build/release/TermGrid /Applications/TermGrid.app/Contents/MacOS/ && cp -R .build/release/TermGrid_TermGrid.bundle /Applications/TermGrid.app/Contents/Resources/`

### Implemented Packs (V4.1 — DO NOT Reimplement)
| Pack | Feature | Status |
|------|---------|--------|
| 016 | Runnable Notebooks — code block Paste/Run in notes | Done + tested |
| 020 | Workspaces — multi-workspace tabs | Done + tested |
| 021 | Skills Storage — CRUD + local scanner | Done + tested |
| 023 | Auto-Project Name | Done + tested |
| 024 | Smart Agent Detection | Done + tested |
| 026 Phase 1 | Ghost Autocomplete — n-gram + trie + GRDB | Done + tested |
| 027 | Draggable Panel Rearrangement | Done + tested |
| 028 | Add Panel Button | Done + tested |
| 029 | Popout Reader View | Done + tested |
| 030 | Project Notes — two-tier notes system | Done + tested |
| 031 | Per-Terminal Close Button | Done + tested |

### Unfinished Packs (V5 — TO IMPLEMENT)

These are the packs to build in V5. They are listed in suggested implementation order (based on dependency and effort).

| Pack | Feature | Effort | Key Notes |
|------|---------|--------|-----------|
| 017 | Inline Media Preview | Medium | Phase 1: verify SwiftTerm's built-in iTerm2/Kitty/Sixel support works. Cap Kitty graphics cache at 64MB per terminal. Phase 2: Cmd+click Quick Look for file paths. |
| 018 | External Secrets Integration | Medium | Import-only (.env files + 1Password CLI). NOT live linkage. No macOS Keychain browsing. |
| 022 | Popout Compose | Medium | Floating overlay on cell (not NSPanel). Shift+Enter sends, Escape dismisses. Cmd+E toggle. |
| 032 | Compose Submit Parity for Codex | High | `Shift+Enter` in compose must fully submit in Codex terminals. No second Enter in the terminal. Preserve shell semantics. |
| 033 | Compose Slash Command Parity | Medium | Slash popup for Claude/Codex compose. When popup is open, `Enter` or `Tab` accepts selection. |
| 019 | Notification V2 | Medium | Research-backed. Extend hook scripts for structured events. Add in-app notification center. Output pattern detection. |
| 015 | SSH Persistence | High | V1 scope: connect/disconnect + saved profiles + reconnect via tmux. NOT auto-reconnect on sleep. Cell model expansion needed. |
| 026 Phase 2 | MLX LLM Enhancement | High | Local Qwen2.5-0.5B Q4, ~300MB download. Separate SPM target (TermGridMLX). Async enhancer when n-gram confidence < 0.6. 150ms debounce. |

#### Pack 017 — Inline Media Preview
- **Spec:** `packs/017-inline-media-preview.md`
- **Core idea:** SwiftTerm already handles iTerm2, Kitty, and Sixel graphics protocols natively. TermGrid just needs to not break it.
- **Phase 1:** Verify `imgcat`, `kitten icat`, `img2sixel` work. Cap Kitty graphics cache budget at 64MB per terminal.
- **Phase 2:** Detect file paths in terminal output. Cmd+click opens macOS Quick Look (`QLPreviewPanel`). Use explicit `file://` or OSC 8 hyperlinks, not regex stdout sniffing.
- **Do NOT:** Implement custom OSC 1337 handlers (SwiftTerm handles these). Do NOT add hover previews (conflicts with terminal mouse reporting).

#### Pack 018 — External Secrets Integration
- **Spec:** `packs/018-external-secrets-integration.md`
- **Core idea:** One-time import into API Locker vault from .env files and 1Password CLI.
- **.env parsing:** `KEY=value`, handle `export`, quoted values, skip comments/blanks. Error on duplicates (skip/replace UI). Ignore variable expansion.
- **1Password:** Check `which op`, run `op item list --categories=api-credential,password --format=json`, show checkboxes for selection.
- **No macOS Keychain browsing** — already using Keychain via `APIKeyVault`. Browsing the whole Keychain is inconsistent UX.

#### Pack 022 — Popout Compose
- **Spec:** `packs/022-popout-compose.md`
- **Core idea:** Pop-out button on compose bar opens a larger floating editor overlay in front of the terminal cell.
- **Size:** ~80% of cell width, 150px tall, expandable by dragging bottom edge.
- **Contains:** Multi-line `NSTextView` (same internals as ComposeBox).
- **Send:** Shift+Enter. **Dismiss:** Escape or click outside. **Toggle:** Cmd+E.
- **Implementation:** `PopOutComposeView` as SwiftUI overlay on `terminalPane` in CellView.

#### Pack 032 — Compose Submit Parity for Codex
- **Spec:** `packs/032-compose-submit-parity.md`
- **Core idea:** `Shift+Enter` from compose must perform a real submit for Codex, not only inject text into the prompt.
- **Expected behavior:** One gesture sends and submits. User should not need to press `Enter` again in the terminal.
- **Important constraint:** Preserve multi-line compose editing and normal shell send behavior. If Codex needs special handling, isolate it behind a single submit path instead of scattering agent checks across views.

#### Pack 033 — Compose Slash Command Parity
- **Spec:** `packs/033-compose-slash-command-parity.md`
- **Core idea:** Claude/Codex compose should offer slash command discovery and selection before submit.
- **Expected behavior:** when the slash popup is visible, `Enter` or `Tab` accepts the highlighted command, `Up/Down` navigates, and `Esc` dismisses.
- **Important constraint:** remap `Enter` only while the slash popup is open. Normal multiline compose behavior should remain unchanged when the popup is closed.

#### Pack 019 — Notification V2
- **Spec:** `packs/019-notification-v2-research.md`
- **Research source:** Grok 4.20 multi-agent analysis (16 agents, 404K tokens).
- **Key improvements:** Extend hook scripts for structured JSON events. Add `summary`/`detail` to `SocketPayload`. In-app notification center view. Output pattern detection for non-agent terminals. Visual cell attention indicators.
- **Depends on:** Pack 024 (Smart Agent Detection) — already implemented.

#### Pack 015 — SSH Persistence
- **Spec:** `packs/015-ssh-persistence.md`
- **V1 scope:** Connect/disconnect SSH, save/load profiles, show visual indicator for SSH sessions, detect disconnection + offer reconnect via remote tmux reattach.
- **Cell model expansion:** Add `sshProfileID: UUID?`, `sessionType: SessionType` (.local | .ssh), `lastRemoteCwd: String?`. Persisted with tolerant decode.
- **V1 does NOT do:** Auto-reconnect on sleep/network change, ControlMaster multiplexing, raw shell reconnect without tmux.

#### Pack 026 Phase 2 — MLX LLM Enhancement
- **Spec:** `packs/026-ghost-autocomplete.md` (Phase 2 section, line ~290)
- **Model:** Qwen2.5-0.5B-Instruct (Q4 quantized, ~300MB). ~50 tokens/sec on M1, ~100+ on M3/M4.
- **Architecture:** Separate SPM target `TermGridMLX` with `mlx-swift` dependency. Conditional linking.
- **Integration:** Async enhancer — n-gram responds in <20ms with ghost text immediately. If confidence < 0.6, dispatch MLX query (150ms debounce). If MLX result is better, replace with smooth crossfade.
- **Model management:** Settings panel with download/remove buttons. Storage at `~/Library/Application Support/TermGrid/models/`.
- **Context window:** Include last 50 lines of terminal output for context-aware predictions.

---

## Critical Bugs Fixed (Learn From These)

These are bugs that were found and fixed in V4.x. They represent patterns that WILL recur if you are not careful. Read all of them before writing code.

### 1. uiState(for:) Infinite Re-Render Loop
**Problem:** `uiState(for:)` in ContentView created new `CellUIState` objects during body evaluation, mutating `@State`, triggering re-renders infinitely.

**Root cause:** Mutating `@State` during SwiftUI body computation is undefined behavior.

**Fix:** Made `uiState(for:)` read-only with a static fallback. States seeded in `onAppear` and `onChange` handlers only.

**Rule:** NEVER write to `@State` inside a computed property or body. Always use `onAppear`/`onChange`/`onReceive`.

### 2. NSHostingView Tooltip Crash
**Problem:** Custom tooltip `NSPanel` used `NSHostingView` as content. When shown during SwiftUI's constraint update cycle, `NSHostingView` triggered re-entrant constraint updates -> `EXC_BREAKPOINT`.

**Root cause:** `NSHostingView` inherently invalidates constraints when added to a window. If the main window is already in a constraint update pass, this re-enters and crashes.

**Fix:** Replaced `NSHostingView` with pure AppKit (`NSTextField` + frame-based layout). NO Auto Layout, NO SwiftUI inside `NSPanel`.

**Rule:** NEVER use `NSHostingView` inside `NSPanel`/`NSWindow` that may be shown during SwiftUI layout. Use pure AppKit for floating panels.

### 3. File Explorer Flip-to-Terminal on Menu Click
**Problem:** Clicking Menu dropdown in `FileExplorerView` caused the view to flip from explorer back to terminal.

**Root cause:** `CellUIState` objects were being recreated during re-renders (same as bug #1).

**Fix:** Same as #1 — read-only `uiState(for:)` + seeding in `onAppear`.

### 4. Ghost Autocomplete Feedback Spiral
**Problem:** Every keystroke penalized the ghost suggestion, even when user was typing the same word manually. Confidence dropped to 0, suggestions died permanently.

**Fix:**
- Only penalize on DIVERGENCE (user types a different character than ghost predicts)
- Confidence floor at 0.3 (can always recover)
- `recordCommand` moved to send handler (not Tab accept) — learns only executed commands
- `ghostFullToken` tracks the complete predicted token for accurate trigram lookup

### 5. SwiftUI .help() Tooltips Do Not Work
**Problem:** SwiftUI's `.help()` modifier on macOS doesn't reliably show tooltips.

**Root cause:** SwiftUI framework bug — `.help()` bridging to AppKit tooltips is broken.

**Fix:** Custom tooltip system using `NSPanel` + `NSTextField` (pure AppKit). `View.tooltip()` extension as drop-in replacement.

---

## Testing

### Running Tests
```bash
swift test  # All 306+ tests must pass
```

### Test Conventions
- Use Swift Testing (`@Test`, `#expect`) not XCTest
- `@Suite` for grouping
- `@MainActor` on test suites that touch UI state
- Use temp directories for persistence tests (`makeTempDir` pattern)
- Clean up with `defer { try? FileManager.default.removeItem(at: dir) }`

### Key Test Helpers
- `WorkspaceStoreTestHelpers` — `makeTempDir`, `makePM`, `makeStore`, `saveWorkspace`
- `PersistenceManager(directory:)` — testable init with custom path

### Test File Locations
```
Tests/TermGridTests/
  CommandRegistryTests.swift
  PersistenceManagerTests.swift
  WorkspaceTests.swift
  WorkspaceCollectionTests.swift
  SkillTests.swift
  SkillsManagerTests.swift
  ... (306 tests across 36 suites)
```

---

## Building and Deploying

### Debug Build
```bash
swift build
swift run TermGrid
```

### Release Build + .app Deploy
```bash
swift build -c release
cp .build/release/TermGrid /Applications/TermGrid.app/Contents/MacOS/
cp -R .build/release/TermGrid_TermGrid.bundle /Applications/TermGrid.app/Contents/Resources/
mdimport /Applications/TermGrid.app
```

### Verify Build
```bash
swift build 2>&1 | tail -3  # Should show "Build complete!"
```

---

## External Advisors

The project uses external AI advisors for design decisions. Consult them before making UI/UX decisions:

| Advisor | Tool | Strength | Notes |
|---------|------|----------|-------|
| Kimi | `kimi-cli` | UI/UX, naming, component layout | Primary UI advisor |
| Gemini | `/opt/homebrew/bin/gemini` | Platform conventions, accessibility | Often rate-limited |
| Codex | `codex exec` | Plan review, code review, architecture validation | Use `/codex-review` |
| MiniMax | API | Deep technical reasoning | |

---

## Conventions

### Code Style
- No emojis in code unless user requests
- Minimal comments — only where logic isn't self-evident
- Keep changes focused — don't refactor unrelated code
- Prefer editing existing files over creating new ones

### Git
- Commit messages: `feat:`, `fix:`, `merge:`, `docs:`, `chore:`
- Always include `Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>`
- Never force-push to main without asking

### SwiftUI Rules
- Use `if/else` (not `ZStack`) for views that shouldn't coexist (terminal/explorer/notes)
- Use `.allowsHitTesting(false)` on overlays that shouldn't intercept events
- Use `DispatchQueue.main.async` for deferred AppKit operations from SwiftUI context
- Use static fallbacks for `@State` dictionary lookups during body evaluation
- NEVER mutate `@State` during body evaluation
- NEVER use `NSHostingView` inside floating `NSPanel`/`NSWindow`
- NEVER use `.help()` for tooltips — use `.tooltip()` (pure AppKit custom system)

---

## Repository Info
- GitHub: https://github.com/Samuel-Tucker/TermGrid
- V4.1 (stable): branch `v4.1` and `main` at `/Users/sam/Projects/TermGrid-V4.1`
- V5 (development): local only at `/Users/sam/Projects/TermGrid-V5`
- Working app: `/Applications/TermGrid.app` (V4.1)
