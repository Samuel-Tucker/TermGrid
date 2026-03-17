# Pack 003: Fix Header Tooltip Clipping

**Type:** Bug Fix
**Status:** Complete
**Date:** 2026-03-16

## Problem

Dock-style hover tooltips on header icon buttons (split, folder, notes) were rendered beneath the terminal/notes body content and clipped by the cell's `clipShape(RoundedRectangle)`. They appeared but were hidden behind the fold.

## Root Cause

The entire `CellView` was wrapped in `.clipShape(RoundedRectangle(cornerRadius: 8))`, which clips all overflow content — including the tooltip overlays that extend beyond the header area.

## Fix

1. Removed the outer `clipShape` from the cell container
2. Replaced it with a `RoundedRectangle` background fill + stroke overlay (border still renders correctly)
3. Added `.clipped()` only to the terminal body `HStack` so terminal content doesn't bleed out
4. Set `.zIndex(1)` on the header so tooltips render above sibling views
5. Flipped tooltips to appear **above** the buttons (`.overlay(alignment: .top)` with negative y offset) so they don't overlap terminal content

## Files Changed

- `Sources/TermGrid/Views/CellView.swift` — Restructured clipping strategy, flipped tooltip alignment

## Testing

- Hover over each header icon button (split H, split V, folder, notes)
- Tooltip label should appear above the button, fully visible, not clipped
- Cell border and rounded corners should still render correctly
