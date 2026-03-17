# TermGrid V2 — Inline Notification System

## What This Repo Is

This is TermGrid V2, forked from V1 (`v1.0.0`). V1 is a stable, daily-use macOS terminal grid app at `/Users/sam/Projects/TermGrid-V1`. **Do not break V1 compatibility** — V2 adds a new subsystem on top.

## V1 Recap (What Already Works)

Native macOS app (SwiftUI + SwiftTerm) displaying a grid of embedded terminal emulators:

- Dynamic grid layout (1x1 to 4x4, GeometryReader fills available space)
- Horizontal + vertical split per cell
- Per-terminal editable labels
- Compose box per terminal (Enter=newline, Shift+Enter=send, collapsible)
- Notes panel per cell (markdown rendering, click-to-edit)
- Working directory picker per cell
- Session restart on process termination
- Warm dark theme (centralised `Theme.swift`)
- App icon with V1 badge
- 30 tests passing

Run with `swift run` or double-click `/Users/sam/Applications/TermGrid.app`

## V2 Goal: iMessage-Style Inline Notifications

### The Problem

You're running 4-6 AI coding agents in TermGrid. You switch to email, Slack, browser to do other work. An agent finishes or needs your input. **Today:** you have to manually check back. **Competitors (cmux, Architect):** put notification badges on the terminal grid — you still have to switch back. Flow broken.

### The Solution

When an agent finishes or needs input, a **macOS native notification** drops in (like iMessage). You reply **inside the notification banner** without leaving your current app. The response pipes back to the agent's PTY. No context switch. Ever.

### Critical Design Constraint

> "If we click the popup and it takes you to a new screen this is WRONG. You deal with that notification in the popup." — Sam

This is non-negotiable. The notification must be self-contained. Click it, reply in it, dismiss it. Never navigate away.

## Decisions Already Made

See `decisions.md` for full details. Summary:

| Decision | Choice |
|----------|--------|
| Target agents | Claude Code + Codex CLI ONLY |
| Detection | Claude Code hooks + Codex `notify` hook |
| Reliability | "Mega reliable, don't care if it takes months" |
| `needs_input` notification | Agent message + inline reply + dismiss |
| `complete` notification | Same inline reply (agent may ask follow-up) + dismiss |
| Heuristic fallback | NO — hooks only, done right |

## Where Brainstorming Left Off

The brainstorming session completed:
1. ✅ Project context exploration
2. ✅ Clarifying questions (2 of ~5 asked)
3. ⬜ Communication channel decision (see `open-questions.md`)
4. ⬜ Propose 2-3 architectural approaches
5. ⬜ Present design sections
6. ⬜ Write spec
7. ⬜ Codex plan review
8. ⬜ Implementation plan
9. ⬜ Build

**Resume by saying:** "Continue TermGrid V2 inline notifications brainstorm"

## File Map

```
docs/v2-handover/
  README.md              — This file
  decisions.md           — All design decisions made so far
  open-questions.md      — Questions still to resolve
  signal-reference.md    — Claude Code + Codex hook payloads
  architecture.md        — V1 codebase architecture guide
```
