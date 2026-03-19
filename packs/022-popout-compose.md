# Pack 022: Pop Out Compose Box

**Type:** Feature Spec
**Priority:** Medium

## Problem

The compose box at the bottom of each terminal is small and collapses. For long prompts or multi-line commands, users need more editing space. When collapsed, there's no quick way to compose without expanding first.

## Solution

Add a "pop out" button to the compose bar that opens it as a larger floating overlay in front of that specific terminal cell.

### UI fit:
- **Pop-out icon** on the compose bar header (small `arrow.up.left.and.arrow.down.right` icon, left of "Compose" text)
- **Works when collapsed** — icon always visible on the collapsed compose bar
- **Floating editor:** Overlays the terminal pane (not the whole window)
- **No new toolbar buttons**

### Floating compose overlay:
- **Size:** ~80% of cell width, 150px tall (expandable by dragging bottom edge)
- **Position:** Centered on the cell, vertically centered in terminal area
- **Styling:** `Theme.cellBackground`, rounded corners (8px), `shadow(radius: 8)`, accent border
- **Contains:** Multi-line `NSTextView` (same as current ComposeBox internals)
- **Send:** Shift+Enter sends to the terminal session, dismisses the overlay
- **Dismiss:** Escape, or click outside the overlay
- **Keyboard shortcut:** `Cmd+E` to toggle pop-out compose on focused cell

### Implementation:
- `PopOutComposeView` — new SwiftUI view, overlay on `terminalPane` in CellView
- Uses existing `ComposeNSTextView` or a new larger `NSTextView` wrapper
- State: `@State private var showPopOutCompose = false` on CellView
- Session reference passed through for `send()`

### Text transfer:
- When popping out: copy current compose box text into the floating editor
- When dismissing (not sending): copy text back to compose box
- When sending: send text, clear both, dismiss overlay

### Risks:
- NSTextView focus management — floating compose must become first responder
- Interaction with agent shutter overlay — pop-out should work even when shutter is active (user might want to send a response)
- Interaction with floating pane — pop-out is per-cell, floating pane has its own compose

### UI impact: Minimal — small icon on compose bar, floating overlay when activated
