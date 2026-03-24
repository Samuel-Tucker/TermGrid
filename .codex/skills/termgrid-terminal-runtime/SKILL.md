---
name: termgrid-terminal-runtime
description: Use for SwiftTerm integration, PTY/session lifecycle, scrollback restore, compose flows, agent detection, and output extraction in TermGrid.
---

# TermGrid Terminal Runtime

Use this skill for anything under `Sources/TermGrid/Terminal` or terminal-adjacent UI.

## Focus Areas
- shell startup and environment injection
- session creation and teardown
- scrollback capture and replay
- agent detection from hooks or terminal output
- compose/send behavior around focused cells and split panes

## Working Rules
- Session lifecycle must be idempotent: start once, kill once, tolerate missing directories.
- Preserve deterministic environment injection such as `TERMGRID_CELL_ID` and `TERMGRID_SESSION_TYPE`.
- Keep detection logic separate from rendering logic.
- Avoid introducing UI coupling into `TerminalSession` unless the state is truly session-owned.

## When Changing Runtime Behavior
1. Read `TerminalSession.swift`, `TerminalSessionManager.swift`, and `LoggingTerminalView.swift`.
2. Identify whether the change affects startup, live output, restore, or shutdown.
3. Check downstream consumers such as notifications, autocomplete context, and label bars.
4. Add or update tests for extractor, manager, or session behavior.

## Validation
- Prefer targeted terminal tests first:
  - `TerminalSessionManagerTests`
  - `TerminalContentExtractorTests`
  - `SessionRestoreTests`
  - `AgentSignalTests` or `SocketServerTests` when detection changes
- Finish with full `swift test`.
