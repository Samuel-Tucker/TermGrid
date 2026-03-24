# TermGrid V5

Build from stable V4.1 base. See docs/V5-HANDOVER.md for full context.

## Essential Rules
- NEVER mutate @State during body evaluation
- NEVER use NSHostingView inside floating NSPanel/NSWindow
- NEVER use .help() for tooltips — use .tooltip() (pure AppKit)
- Always run `swift test` after changes (306+ tests must pass)
- Read pack specs before implementing
- Use /codex-review for second opinions on plans

## Quick Commands
- Build: `swift build`
- Test: `swift test`
- Run: `swift run TermGrid`
- Deploy: `swift build -c release && cp .build/release/TermGrid /Applications/TermGrid.app/Contents/MacOS/`
