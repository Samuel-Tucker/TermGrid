---
name: termgrid-notifications-hooks
description: Use for TermGrid agent notifications, hook installation, socket payload changes, badge and shutter behavior, message parsing, and reply routing.
---

# TermGrid Notifications Hooks

Use this skill for `Notifications/` and agent event UX.

## Responsibilities
- hook script deployment
- socket payload shape and decoding
- message parsing and summaries
- notification posting and reply routing
- agent badge and busy-state consistency

## Rules
- Prefer structured events over brittle text parsing.
- Keep wire payloads simple and forward-compatible.
- Preserve graceful behavior for unknown or malformed input.
- Badge state, shutter state, and notification state should agree on agent lifecycle.

## Change Workflow
1. Read the relevant spec or handover section first.
2. Inspect `AgentSignal.swift`, `HookInstaller.swift`, `NotificationManager.swift`, and parser/socket files.
3. Check terminal session env injection if hook context changes.
4. Add or update parser and socket tests before touching UI affordances.

## Validation
- Target:
  - `AgentSignalTests`
  - `MessageParserTests`
  - `SocketServerTests`
- Then run full `swift test`.
