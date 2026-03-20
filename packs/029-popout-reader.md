# Pack 029: Popout Reader View

**Type:** Feature Spec
**Priority:** High
**Competitors:** iTerm2 "Maximize Pane", Warp "Focus Mode", VS Code terminal maximize

## Problem

Agent responses (Claude, Codex, etc.) can be long and detailed — code blocks, explanations, diffs. Reading them in a small grid cell is painful. Users need a way to pop out the most recent agent output into a full-size, readable view without disrupting the grid layout.

## Solution

A "Popout" button on each terminal panel that captures the most recent agent message/output block and renders it in a large overlay or sheet with proper formatting, syntax highlighting, and scroll.

### UI fit:
- **Trigger button:** Eye icon (`eye`) or expand icon (`arrow.up.left.and.arrow.down.right`) on the cell label bar, next to the split buttons
- **Popout view:** Full-window overlay (not a separate window) with:
  - Dark background matching `Theme.appBackground`
  - Content area: 80% of window width, vertically scrollable
  - Header: cell label + agent badge + "Close" button (X) + "Copy All" button
  - Content rendered as formatted markdown (using existing MarkdownUI dependency)
  - Code blocks with syntax-highlighted backgrounds
  - Dismiss: click X, press Escape, or click outside the content area
- **No new window** — stays within the main TermGrid window as a modal overlay (like command palette)

### Content extraction:
- **Strategy:** Capture the last N lines of terminal output (scrollback buffer) from the cell's `TerminalSession`
- Use `TerminalSession.getTerminalContent()` or `getRawScrollback()` to get the text
- **Heuristic for "most recent message":** Walk backward from the cursor position, stop at the last shell prompt line (detect `$`, `❯`, `%`, or the detected agent's prompt pattern)
- Fallback: if prompt detection fails, show the last 200 lines
- Strip ANSI escape sequences for clean text rendering

### Interaction:
- **Scroll:** Standard macOS scroll in the overlay
- **Text selection:** Enabled — user can select and copy portions
- **Copy All:** Copies the entire extracted content to clipboard
- **Keyboard:** `Cmd+Shift+E` to popout focused cell's output ("E" for expand)
- **Command palette:** "Popout Terminal Output"

### Data model:
- No persistent state — popout is ephemeral, reads from live scrollback
- `PopoutReaderView` struct with `terminalContent: String` and `cellLabel: String`
- Optional: `agentType: AgentType?` for badge display

### Risks:
- ANSI stripping may lose meaningful formatting (colors indicating errors vs success) — consider offering raw vs clean toggle
- Prompt detection heuristic will fail for non-standard shells or agents with unusual prompts — fallback to last-N-lines is safe
- Large scrollback buffers (10k+ lines) may cause UI lag in markdown rendering — cap at 500 lines with "Show more" pagination
- Terminal content is live — if agent is still streaming, popout shows a snapshot (not live-updating)
