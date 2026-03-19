# Pack 022: Pop Out Compose Box

**Type:** Feature Spec
**Priority:** Medium

## Problem

The compose box at the bottom of each terminal is small and collapses. For long prompts or multi-line commands, users need more space. When collapsed, there's no way to compose without expanding it first.

## Solution

Add a "pop out" option to the compose box that opens it as a floating overlay in front of that terminal. Works even when the compose box is collapsed.

### UI:
- Small pop-out icon on the compose bar (next to the collapse chevron)
- Click opens a larger floating text editor overlaying the terminal
- Same send behavior (Shift+Enter = send)
- Escape or click outside to dismiss
- Sent text goes to the same terminal session

### Sizing:
- Floating compose: ~80% of cell width, ~150px tall
- Centered vertically on the cell
- Rounded corners, shadow, themed background
