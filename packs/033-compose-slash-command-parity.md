# Pack 033: Compose Slash Command Parity

**Type:** UX / behavior fix
**Priority:** High

## Problem

Slash commands in Claude Code and Codex work interactively in the terminal, but TermGrid's compose surfaces were plain text editors. Users could type `/...` in compose, but they did not get any command discovery or autocomplete help before submission.

That created a mismatch between:
- terminal-native Claude Code / Codex behavior
- phantom compose
- classic compose
- floating pane compose

## V1 Solution

Add a compose-native slash-command popup for agent sessions.

### Scope
- Support slash command discovery in compose when the active session is:
  - `claudeCode`
  - `codex`
- Show a filtered popup while the current compose line starts with `/`
- Support:
  - `Enter` to accept the selected slash command when the popup is open
  - `Tab` to accept the selected slash command
  - `Up/Down` to move through suggestions
  - click to select a suggestion
- Keep `Shift+Enter` as the submit gesture
- Do not change shell compose semantics for non-agent sessions

### Command sources
- **Claude Code**
  - built-in commands
  - user commands from `~/.claude/commands`
  - project commands from `<working-directory>/.claude/commands`
- **Codex**
  - built-in commands only for V1

## Non-goals

- Do not try to reproduce each agent's full terminal UI inside compose
- Do not change plain `Enter` behavior inside compose editing when the slash popup is not visible
- Do not add MCP-driven slash command discovery in V1
- Do not block normal multiline compose

## Implementation Notes

- Keep filtering and command replacement in a pure model seam so it can be tested without UI automation.
- Wire the popup into both `ComposeBox` and `PhantomComposeOverlay`.
- When slash popup is active, it takes precedence over ghost autocomplete on `Tab`.
- When slash popup is active, it also temporarily takes precedence over newline behavior on `Enter`.
- The compose editor should treat slash-popup-open as a transient selection mode:
  - `Enter` = accept selected command
  - `Up/Down` = change selection
  - `Esc` = dismiss popup
  - `Shift+Enter` = still submit compose text if the user intentionally bypasses the popup

## UX Decision

This is the intended behavior:
- slash popup closed:
  - `Enter` keeps its normal compose meaning
  - `Shift+Enter` submits
- slash popup open:
  - `Enter` accepts the highlighted slash command
  - `Tab` also accepts
  - `Shift+Enter` still submits

Rationale:
- once the slash popup is open, the user is in command-selection mode, not plain text-entry mode
- requiring click-only or Tab-only acceptance is weaker than Claude/Codex terminal behavior
- remapping `Enter` only while the popup is visible avoids breaking normal multiline compose

## Validation

- Focused tests for query extraction, replacement, and command discovery
- Full `swift test`
