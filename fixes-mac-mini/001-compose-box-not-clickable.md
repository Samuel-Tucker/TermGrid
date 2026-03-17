# Fix: Compose Box Not Clickable on Mac Mini

**Date:** 2026-03-16
**File:** `Sources/TermGrid/Views/ComposeBox.swift`

## Symptom

Compose box renders but does not accept mouse clicks or keyboard input on Mac Mini. Works fine on Mac Studio.

## Root Cause

The `ComposeNSTextView` (inside an `NSScrollView`, wrapped in `NSViewRepresentable`) was created without an initial frame, `autoresizingMask`, or explicit container sizing. This caused the NSTextView to have a zero-sized frame inside the scroll view — clicks passed straight through it to the terminal view behind.

The Mac Studio likely worked due to differences in display scaling, macOS version, or how the app was launched (Xcode vs SPM-built .app bundle).

## Fix

In `ComposeTextEditor.makeNSView()`:

1. **Set initial frame** — `ComposeNSTextView(frame: NSRect(origin: .zero, size: contentSize))` instead of bare `ComposeNSTextView()`
2. **Set `autoresizingMask = [.width]`** — so the text view resizes with the scroll view
3. **Set `textContainer?.containerSize`** — with proper width and unlimited height
4. **Set `minSize`** — `NSSize(width: 0, height: 28)` so it always has clickable area
5. **Explicitly set `isEditable = true` and `isSelectable = true`**
6. **Added `mouseDown` override** — calls `window?.makeFirstResponder(self)` to reclaim focus from terminal view
