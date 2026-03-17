# Pack 002: Dock-Style Hover Magnification for Header Icons

**Type:** Feature
**Status:** Complete
**Date:** 2026-03-16

## Goal

Add macOS Dock-inspired hover interaction to the 4 header icon buttons (split horizontal, split vertical, folder/repo, notes). When a user hovers an icon:

1. The hovered icon magnifies smoothly (scale up)
2. Immediate neighbor icons scale up partially (proximity cascade)
3. Non-hovered icons blur slightly — depth-of-field focus pull
4. A text label appears above showing the button's function
5. Lateral movement (left→right, right→left) feels smooth — no jarring pops

## Design Decisions

### Scale Factors (adapted for compact 12pt header context)
- **Hovered icon:** 1.35x (12pt → ~16pt perceived)
- **Immediate neighbors:** 1.12x (subtle cascade)
- **Others:** 1.0x (no change)

### Blur
- **Hovered:** 0px
- **Neighbors:** 0.5px (very subtle)
- **Others:** 1.5px (noticeable but not heavy)

### Animation
- Spring: `response: 0.3, dampingFraction: 0.75` — snappy, natural, no overshoot
- Lateral movement handled by onHover exit → enter cascading through spring

### Tooltip
- 9pt medium weight label above icon
- Fade in + slide up on hover
- Background pill matching header background with shadow

### Color
- Hovered icon: accent color (#C4A574) instead of default (#7A756B)
- Others remain default headerIcon color

## Advisor Input

- **Gemini:** Proximity-based scaling, spring(0.35, 0.8), 2.5px blur, VisualEffectView for native feel
- **Kimi:** Unavailable (auth error)

Values tuned down from Gemini's standalone toolbar recommendations to fit a compact cell header bar.

## Files Changed

- `Sources/TermGrid/Views/CellView.swift` — Added hoveredHeaderButton state, headerIconButton helper, refactored header buttons

## Testing

- Hover each icon — should magnify with accent color
- Move mouse laterally across all 4 icons — smooth cascade, no pops
- Tooltip text should appear above each icon on hover
- Non-hovered icons should blur subtly
- Verify no layout shift/clipping in header bar
