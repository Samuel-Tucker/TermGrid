# Pack 024: Smart Terminal Agent Detection

**Type:** Feature Spec
**Priority:** Medium
**Reference:** King Conch Terminal

## Problem

TermGrid has hook-based agent detection (Claude Code, Codex) but no visual branding. Users can't see at a glance which agent is running in which terminal.

## Solution

Detect running agents and show branded indicators in the terminal header — logos, styled labels, and color accents per agent type.

### Detection:
- Existing hook system already identifies Claude Code and Codex via `AgentType` enum
- Extend to detect agent from terminal output patterns (startup banners)
- Add detection for: Claude Code, Codex, Gemini CLI, Aider, Cursor Agent

### UI:
- Agent logo/icon in the terminal label bar (small, left of the label)
- Styled agent name badge: "CLAUDE", "CODEX", "GEMINI" etc.
- Agent-specific accent colors on the label bar
- Clear when agent exits

### Assets:
- Small monochrome icons per agent (8-12px)
- Color palette per agent matching their branding
- See King Conch Terminal for reference implementation
