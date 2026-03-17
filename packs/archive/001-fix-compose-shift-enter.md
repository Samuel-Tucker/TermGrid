# Pack 001: Fix Compose Box Shift+Enter in Bundled App

**Type:** Bug Fix
**Status:** Complete
**Date:** 2026-03-16

## Problem

Shift+Enter in the ComposeBox no longer sends text to the terminal when running the bundled `.app`. This worked previously when running from Xcode/CLI.

## Root Cause

In a bundled macOS app, key events flow through `performKeyEquivalent:` on the responder chain **before** `keyDown:` is called on the first responder. The app's menu system or SwiftUI's internal key handling consumes the Shift+Enter event at the `performKeyEquivalent` stage, so `ComposeNSTextView.keyDown(with:)` never receives it.

## Fix

Override `performKeyEquivalent(with:)` in `ComposeNSTextView` to intercept Shift+Enter at the earlier event dispatch stage, returning `true` to mark it as handled.

## Files Changed

- `Sources/TermGrid/Views/ComposeBox.swift` — Added `performKeyEquivalent` override to `ComposeNSTextView`

## Testing

- Open a new instance of the bundled app (do not close running V1)
- Type text in compose box
- Press Shift+Enter — text should send to terminal
- Press plain Enter — should insert newline as before
