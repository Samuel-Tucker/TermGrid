# Pack 017: Inline Media Preview in Terminal

**Type:** Feature Spec
**Priority:** Low
**Competitors:** Wave, iTerm2, Kitty

## Problem

When terminal output references images, users must open them externally.

## Split into two phases (per Codex feedback):

### Phase 1: Enable built-in inline graphics (V1)
SwiftTerm already handles iTerm2, Kitty, and Sixel graphics protocols natively. TermGrid just needs to not break it.

**What to do:**
- Verify `imgcat`, `kitten icat`, and `img2sixel` work in TermGrid terminals
- Set Kitty graphics cache budget: cap at 64MB per terminal (default is 320MB — dangerous in a multi-cell app)
- If protocols already work via SwiftTerm's built-in handling: document it, ship it, done
- If not: investigate what's blocking (likely nothing — `LocalProcessTerminalView` should handle this)

**What NOT to do:**
- Do NOT implement custom `OSC 1337` handlers — SwiftTerm already handles these. A custom handler will fight the library.
- Do NOT add hover previews over terminal content — conflicts with selection, dragging, and SwiftTerm's mouse reporting

### Phase 2: File path preview (V2, separate pack)
- Detect file paths in terminal output
- Cmd+click opens macOS Quick Look (`QLPreviewPanel`)
- Use click/context-menu, NOT hover (hover conflicts with terminal interaction)
- Use explicit `file://` or OSC 8 hyperlinks, not regex stdout sniffing
- Note: SwiftTerm already uses Cmd+click for hyperlink payloads — need to extend, not replace

### Memory budget:
- Test matrix before shipping: `imgcat test.png`, `kitten icat test.png`, `img2sixel test.png`
- Monitor memory with 9 cells each displaying images
- Hard cap: 64MB Kitty cache per terminal, 576MB total for 3x3 grid

### UI fit:
- **Zero new UI elements.** Images appear inline in terminal output automatically.
- Phase 2 adds Cmd+click behavior (no buttons)

### UI impact: Zero new chrome
