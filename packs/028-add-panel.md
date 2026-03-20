# Pack 028: Add Panel Button (Mini-style)

**Type:** Feature Spec
**Priority:** Medium
**References:** TermGrid-Mini-V1 ContentView — horizontally-tiled "Add Panel" button

## Problem

Adding a new terminal panel requires changing the grid preset from the toolbar picker, which is indirect and unintuitive. In TermGrid Mini V1, there was a simple "+" button at the edge of the grid that added a new panel inline — users loved the directness.

## Solution

An "Add Panel" button rendered at the trailing edge of the grid (right side or bottom, depending on layout) that adds a new cell and auto-expands the grid preset to accommodate it.

### UI fit:
- **Button placement:** After the last visible cell in the grid — right edge for single-row layouts, bottom-right for multi-row
- **Appearance:** Dashed rounded rectangle (same size as a cell would be, or a compact 60px-wide strip) with `+` icon and "Add Panel" label
- **Colour:** `Theme.divider` border, `Theme.notesSecondary` text, `Theme.accent` on hover
- **Hover:** Border transitions to `Theme.accent`, slight scale-up (1.01x)
- **Animation:** New cell slides in from the right (easeInOut 0.2s)
- **Hidden when:** Grid is at max preset (3×3 = 9 cells)

### Behaviour:
- Click "Add Panel" → append new `Cell()` to `workspace.cells` → bump grid preset to next size that fits
- Grid preset auto-escalation: 1×1 → 2×1 → 2×2 → 3×2 → 3×3
- New cell gets default working directory (`~`), empty label, no notes
- Terminal session created lazily on cell appear (existing behaviour)
- If at max grid (3×3), button is hidden — user must close a panel first

### Data model:
- No new models — uses existing `WorkspaceStore.setGridPreset()` + cell append
- New method: `WorkspaceStore.addPanel()` that encapsulates the preset bump + cell creation

### Keyboard shortcut:
- `Cmd+Shift+N` — add new panel (mirrors "New" conventions)
- Command palette: "Add Panel"

### Risks:
- Grid preset escalation may not match user's preferred layout direction (e.g. user wants 1×2 not 2×1) — could offer horizontal vs vertical expansion in context menu
- Button sizing in small windows — degrade to icon-only when cell width < 120px
