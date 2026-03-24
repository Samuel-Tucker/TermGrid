# Pack 036: Hover Focus Dimming

**Type:** Feature Spec
**Priority:** Low
**Advisors:** Kimi (menu bar toggle), Gemini (Settings scene with AppStorage)

## Problem

In a multi-panel grid, all panels compete for visual attention equally. When focused on one panel, the others are distracting.

## Solution

When hovering over a panel, other panels dim slightly (opacity overlay). Toggled via a Settings pane (Cmd+,) using `@AppStorage` for persistence.

### UI

- Hovering a cell applies a dark overlay (~0.35 opacity) to all other cells
- Smooth fade transition (0.15s)
- Toggle in Settings scene: "Dim inactive panels on hover"
- `@AppStorage("hoverDimmingEnabled")` — defaults to off
- Also accessible via View menu: "Dim Inactive Panels" (Cmd+Shift+D)

### Implementation

1. Add `Settings` scene to `TermGridApp` with a `SettingsView`
2. Add `@AppStorage("hoverDimmingEnabled")`
3. Read in ContentView's cell rendering — overlay black at 0.35 when another cell is hovered
4. Use existing `hoveredCellID` state
5. Add View menu toggle with keyboard shortcut
