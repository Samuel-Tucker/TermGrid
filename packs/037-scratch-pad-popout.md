# Pack 037: Scratch Pad Pop-Out

**Type:** Feature Spec
**Priority:** Medium
**Advisors:** Kimi (floating overlay pattern), Gemini (utility window or popover)
**Reference:** King Conch NotepadView (dock/undock pattern)

## Problem

The scratch pad in the notes sidebar is tiny (~80px tall). Writing anything substantial is uncomfortable. The font color is too dim to read comfortably.

## Solution

1. **Pop-out button** on the scratch pad header — opens a floating overlay for comfortable editing
2. **Brighter font color** for scratch pad text — more readable

### Pop-out design

- Floating overlay (consistent with existing FloatingPaneView pattern)
- Draggable title bar, resizable via bottom-right grip
- Default size: 400x300, min 300x200, max 600x500
- Dark scrim behind overlay (click to dismiss + save)
- TextEditor with monospace font at 13pt
- Syncs content back to scratch pad on dismiss
- Pop-out button: `arrow.up.left.and.arrow.down.right` icon next to "SCRATCH PAD" label

### Font color fix

- Change scratch pad text from `Theme.notesText` (#A09A8E) to a brighter variant
- Kimi palette suggests ~#C4BEB5 (warmer, brighter, still not pure white)
- Apply to both inline TextEditor and pop-out TextEditor

### Implementation

1. Add `scratchPadBrightText` color to Theme.swift
2. Add pop-out button to NotesView scratch pad header
3. Create ScratchPadPopoutView as floating overlay
4. Wire through CellView/ContentView as overlay
5. Sync content on dismiss
