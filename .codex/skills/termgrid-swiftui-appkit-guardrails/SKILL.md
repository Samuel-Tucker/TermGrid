---
name: termgrid-swiftui-appkit-guardrails
description: Use for SwiftUI and AppKit boundary work in TermGrid, especially floating UI, tooltips, Observation state, NSView-backed terminals, and layout-timing bugs.
---

# TermGrid SwiftUI AppKit Guardrails

Use this skill when touching `Views/`, terminal wrappers, floating panels, or event-heavy UI.

## Hard Rules
- Never mutate `@State` or observable state during `body` evaluation.
- Never use `NSHostingView` inside floating `NSPanel` or `NSWindow` surfaces that can appear during layout.
- Use pure AppKit for fragile floating chrome such as tooltips and timing-sensitive overlays.
- Keep NSView-backed terminal concerns out of generic SwiftUI state when possible.

## Safe Patterns
- Seed or repair state in `onAppear`, `onChange`, `onReceive`, or explicit actions.
- Use small view models or state carriers for per-cell ephemeral behavior.
- Treat hover, focus, and gesture interactions as timing-sensitive when a SwiftTerm view is nearby.
- Prefer explicit overlay ownership over hidden global state.

## Red Flags
- computed properties that create or mutate state
- any new `NSHostingView` inside custom window/panel code
- gesture handlers layered on top of terminal content without testing hit behavior
- layout work that assumes SwiftUI update order

## Files To Inspect
- `Sources/TermGrid/Views/ContentView.swift`
- `Sources/TermGrid/Views/*.swift`
- `Sources/TermGrid/Terminal/*.swift`
- `Sources/TermGrid/Theme.swift`

## Validation
- Reproduce hover, focus, and open/close flows manually if UI timing changed.
- Run the most relevant UI-adjacent suites plus full `swift test`.
