# Pack 035: Panel Header Colors

**Type:** Feature Spec
**Priority:** Medium
**Depends on:** None
**Advisors:** Kimi (UI pattern), Gemini (HIG + WCAG)

## Problem

In a 2x2 or 3x3 grid, all panels look identical. Users can't quickly distinguish which panel is which at a glance. The only differentiator is the text label, which requires reading.

## Solution

Add per-panel color coding via a colored dot next to the panel name and a subtle background tint on the header bar. Same mechanism for the notes sidebar header. Users pick from a constrained 8-color muted palette.

### UI pattern (informed by Kimi + Gemini)

- **8px colored dot** next to the panel name (Apple HIG canonical — Finder tags, Calendar)
- **15% opacity background tint** on the entire header bar for at-a-glance grouping
- Click dot → inline palette popup (8 swatches + clear/none)
- Notes sidebar: same dot next to "NOTES" label

### Palette (Kimi's desaturated warm palette, verified for WCAG AA on dark)

| Name | Hex | 15% tint on #1E1E22 |
|------|-----|---------------------|
| Rose | #B86A6A | Subtle warm red |
| Rust | #B87B5C | Warm orange-brown |
| Gold | #B89A5C | Near-amber |
| Sage | #7A9B7A | Desaturated green |
| Teal | #5A9B8F | Cool terminal-adjacent |
| Steel | #5C7A9B | Neutral blue |
| Lavender | #9B8AB8 | Soft purple |
| Slate | #6A7A8A | Gray-blue neutral |

### Data model

- Add `headerColor: String?` to `Cell` (hex string, nil = no color)
- Tolerant decode with nil default
- Add `updateHeaderColor(_:for:)` to `WorkspaceStore`

### Implementation

1. Add `PanelColor` enum to `Theme.swift`
2. Add `headerColor` field to `Cell` model with tolerant decode
3. Add `updateHeaderColor` to `WorkspaceStore`
4. Add color dot + popup to `CellView.headerView`
5. Apply header background tint in `CellView`
6. Add color dot + popup to `NotesView.notesHeader`
7. Apply notes header background tint
