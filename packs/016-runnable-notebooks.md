# Pack 016: Runnable Notebooks

**Type:** Feature Spec
**Priority:** Medium
**Competitors:** Warp

## Problem

The notes panel supports markdown text but code blocks are static. Users can't execute code snippets from their notes directly in the terminal.

## Solution

Enhance the notes panel so fenced code blocks become executable — but with important distinctions from the original spec, per Codex review.

### Key design decisions (Codex feedback):

1. **Two actions, not one:** "Paste" (insert text into terminal) and "Run" (paste + execute). Default is Paste. Run only available for shell fences.
2. **Shell fences only for Run:** Only `bash`, `sh`, `zsh`, or untagged fences get a Run button. `python`, `json`, `sql`, etc. get Paste only.
3. **Preserve raw block exactly** — do NOT reuse compose box's per-line splitting. Send the entire block as a single bracketed paste (`\e[200~...\e[201~`) to avoid breaking heredocs, multi-line commands, and blank lines.
4. **Target the focused pane** when splits exist. Show a subtle indicator of which pane will receive ("→ primary" or "→ split").

### UI fit:
- **No new buttons or panels.** Enhances existing notes panel.
- **Code blocks get two buttons on hover** (top-right corner):
  - 📋 Paste (always available) — inserts code into terminal as bracketed paste
  - ▶ Run (shell fences only) — same as paste, but appends `\r` to execute
- **Visual feedback:** Brief green flash on code block border after action
- **Disabled state:** If terminal is hidden (explorer showing) or session ended, buttons are grayed out with tooltip "Terminal not active"

### Notes panel tap conflict:
- Currently, tapping rendered markdown enters edit mode. Code block action buttons must use `.onTapGesture` with `.highPriorityGesture` to prevent triggering edit mode when clicking the buttons.

### Implementation approach:
- MarkdownUI exposes `content` and `language` in `CodeBlockConfiguration`
- Custom `Theme.codeBlock` style that wraps the block with an overlay for hover buttons
- Need to pass `session.send` callback through to NotesView (add `onSendToTerminal: (String) -> Void` callback)
- Bracketed paste: `"\u{1b}[200~" + code + "\u{1b}[201~"` for Paste, same + `"\r"` for Run

### UI impact: Zero new chrome — just hover buttons on existing code blocks
