# Pack 024: Smart Terminal Agent Detection

**Type:** Feature Spec
**Priority:** Medium
**Reference:** King Conch Terminal (`/Users/sam/Projects/King-Conch-Terminal-MacOS-V1`)

## Problem

TermGrid has hook-based agent detection (Claude Code, Codex) but no visual branding. Users can't see at a glance which agent is running in which terminal.

## Solution

Detect running agents and show branded indicators in the terminal label bar — icons, styled name badges, and status indicators.

### Detection methods:
1. **Hook signals (existing):** `AgentSignal` with `agentType` (.claudeCode, .codex) already fires on Start/Stop/Notification events via SocketServer
2. **Terminal output patterns (new):** Detect agent startup banners in terminal output:
   - Claude Code: `╭─ Claude` or `Claude Code` in first ~20 lines
   - Codex: `OpenAI Codex` or `codex-cli` startup banner
   - Gemini CLI: `Gemini` startup banner
   - Aider: `aider` startup banner
3. **Extend AgentType enum:** Add `.gemini`, `.aider`, `.unknown`

### UI fit:
- **Agent badge** in the `TerminalLabelBar` (left of the terminal label text)
- Badge shows: small icon + agent name in colored pill
- Colors per agent:
  - Claude: `#D4A574` (warm amber, matches Theme.accent)
  - Codex: `#75BE95` (green, matches Theme.staged)
  - Gemini: `#4285F4` (Google blue)
  - Aider: `#FF6B6B` (coral)
  - Unknown agent: `Theme.headerIcon` (gray)
- Badge appears when agent is detected, disappears when agent exits
- Agent shutter overlay (Pack 013) shows the agent name from this detection

### Agent state on TerminalSession:
```swift
var detectedAgent: AgentType? = nil
```
- Set via hook signal OR output pattern detection
- Cleared when process terminates or new process starts

### TerminalLabelBar changes:
- Currently shows: editable label text
- New: `[agent badge] [label text]`
- Badge is non-interactive (just visual indicator)

### King Conch reference patterns:
- King Conch uses COP (Conch Output Protocol) — OSC escape sequences
- TermGrid uses hook scripts + output pattern matching instead (simpler, no protocol dependency)
- King Conch visual: pane border color changes per agent state
- TermGrid already has border pulse (Pack 013) — extend with agent-specific colors

### Risks:
- False positive detection from terminal output (e.g., user types "claude" in a command)
- Mitigate: only detect in first 20 lines after process start, require specific patterns
- Output pattern detection runs in `LoggingTerminalView.dataReceived` — same thread safety concerns as Pack 013 (dispatch to MainActor)

### UI impact: Low — small badge in terminal label bar, no new buttons or panels
