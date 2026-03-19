# Pack 013: Agent Notifications

**Type:** Feature Spec
**Priority:** Medium
**Competitors:** cmux

## Problem

When running long AI agent tasks, users switch away and miss when the task completes or needs attention.

## Solution

Monitor terminal output for patterns and show visual indicators + optional macOS notifications.

### Core insight from Codex review:
A border glow alone doesn't solve the "switched away" problem. Must include **macOS system notifications** for error/attention severity, so users get notified even when TermGrid isn't focused.

### UI fit:
- **Notification dot:** 6px colored circle to the left of the cell label. Clears only when the user **scrolls to the bottom of the terminal** (not just on focus — Codex correctly flagged that Ctrl+Tab focus cycling would clear unread notifications prematurely).
- **Cell border pulse:** 3-second accent-color glow on trigger (visual in-app).
- **macOS notification:** For `error` and `attention` severity only. Opt-in via system notification permissions.
- **No new header buttons.**

### Default trigger patterns (narrowed per Codex feedback):
| Pattern | Severity |
|---|---|
| `Build complete!` | success (green) |
| `✓ Test run with .* passed` | success (green) |
| `error:` at line start (anchored) | error (red) |
| `FAIL` at line start (anchored) | error (red) |
| `? ` at line start after `>` prompt | attention (amber) |

**Removed from original spec:** Raw `PASS`, `ERROR`, `$`, `%` — too many false positives with normal shell output, logs, and agent transcripts.

### Split pane handling:
- Store notification state on the **session**, not the view (`@State` is too fragile — disappears on re-render/grid changes)
- Track `unreadSeverity`, `sourcePane` (primary/split), `matchedPattern`, `timestamp` on `TerminalSessionManager`
- Cell renders aggregate badge from both panes

### Implementation risks:
- **Output capture is non-trivial.** `TerminalContainerView` delegate doesn't expose raw output. Need to hook SwiftTerm's terminal buffer or add a `TerminalViewDelegate` callback.
- **ANSI escapes, spinners, TUI apps** — scan normalized text only, not raw bytes. Use SwiftTerm's buffer `getLine()` API to read visible text.
- **Notification dot vs SSH indicator (Pack 015):** Both want space near the label. Use a single status area with priority: error > attention > SSH > success.

### Notification dot colors:
- Success: `#75BE95`
- Error: `#E06C75` (add to Theme)
- Attention: `Theme.accent` (#C4A574)

### Settings:
- Default patterns ship with app
- User customization via `~/.termgrid/notifications.json` deferred to V2

### UI impact: Minimal — 6px dot + occasional border glow + system notifications
