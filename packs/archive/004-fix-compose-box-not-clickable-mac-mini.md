# Pack 004: Fix Compose Box Not Clickable on Mac Mini

**Type:** Bug Fix
**Status:** Complete
**Date:** 2026-03-16

## Problem

Compose box rendered but did not accept mouse clicks or keyboard input on Mac Mini. Worked fine on Mac Studio.

## Root Cause

The `ComposeNSTextView` inside the `NSViewRepresentable` was created with default `NSTextView()` (zero frame), no `autoresizingMask`, and no explicit container sizing. The NSTextView ended up zero-sized inside the scroll view — clicks passed through it to the terminal view behind.

## Fix

In `ComposeTextEditor.makeNSView()`:

1. Set initial frame: `ComposeNSTextView(frame: NSRect(origin: .zero, size: contentSize))`
2. Added `autoresizingMask = [.width]` so text view resizes with scroll view
3. Set `textContainer?.containerSize` with proper width and unlimited height
4. Set `minSize = NSSize(width: 0, height: 28)` for guaranteed clickable area
5. Explicitly set `isEditable = true` and `isSelectable = true`
6. Added `mouseDown` override calling `window?.makeFirstResponder(self)` to reclaim focus from terminal view

## Files Changed

- `Sources/TermGrid/Views/ComposeBox.swift` — NSTextView frame/sizing setup, mouseDown override

## Testing

- Click into compose box — cursor should appear and accept typing
- Click terminal, then click compose box again — focus should transfer correctly
