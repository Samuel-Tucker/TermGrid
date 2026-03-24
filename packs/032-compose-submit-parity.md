# Pack 032: Compose Submit Parity for Codex

**Type:** Bugfix Spec
**Priority:** High

## Problem

In TermGrid’s compose UI, `Shift+Enter` is advertised as “send”, but in Codex terminals the current behavior can stop at “insert prompt text into the terminal input”. The user then has to press `Enter` again inside the terminal to actually submit the message.

That is bad UX for two reasons:
- It violates the compose hint text and user expectation.
- It differs from Claude Code behavior, where `Shift+Enter` from compose submits the message end-to-end in one action.

The product rule should be simple: when the user presses `Shift+Enter` in compose, the message should be fully submitted to the active terminal interaction. No second confirmation keystroke inside the terminal should be required.

## Solution

Standardize compose “send” semantics around **submit**, not merely **text injection**.

### Product behavior
- `Shift+Enter` in compose must:
  - send the compose text to the active terminal session
  - perform the terminal submit action in the same gesture
  - dismiss phantom/pop-out compose if applicable
  - return focus to the terminal
- This must work for Codex with the same one-step feel users already expect from Claude Code.

### Scope
- **Primary fix target:** Codex sessions (`session.detectedAgent == .codex`)
- **Compose surfaces that must behave consistently:**
  - phantom compose overlay
  - classic compose box
  - floating pane compose
  - pop-out compose when Pack 022 is implemented

### Non-goal
- Do not change plain `Enter` behavior inside compose editing.
- Do not remove multi-line editing support.
- Do not regress normal shell command sending.

## Implementation direction

The key bug is likely that some paths treat compose send as “paste text into PTY” instead of “submit the current prompt”.

### Expected architecture
- Introduce a single helper for compose submission, rather than hand-rolled send logic in multiple views.
- That helper should clearly separate:
  - **payload insertion**
  - **submit keystroke**
  - **agent-specific behavior if needed**

### Suggested shape
- Add a session-level submit method or a small compose sender utility used by all compose surfaces.
- Example API shape:

```swift
func submitComposePayload(_ text: String, for session: TerminalSession)
```

or

```swift
extension TerminalSession {
    func submitComposeText(_ text: String)
}
```

### Behavioral rules
- Single-line prompt:
  - inject text
  - issue the submit keystroke in the same path
- Multi-line prompt:
  - preserve current line-by-line execution semantics for shell workflows unless Codex-specific handling requires a different path
- Codex detection:
  - if a special submit path is needed for Codex, make it explicit and isolated
  - do not hide agent-specific behavior across unrelated UI code

## Files likely involved
- `Sources/TermGrid/Views/ComposeBox.swift`
- `Sources/TermGrid/Views/CellView.swift`
- `Sources/TermGrid/Views/FloatingPaneView.swift`
- `Sources/TermGrid/Terminal/TerminalSession.swift`
- agent detection state from `Sources/TermGrid/Notifications/AgentSignal.swift`

## Validation

### Manual validation
1. Focus a terminal running Codex.
2. Open compose.
3. Type a prompt.
4. Press `Shift+Enter`.
5. Expected: the prompt is submitted immediately. No extra `Enter` in the terminal is needed.

Repeat for:
- phantom compose
- classic compose
- floating pane compose
- Claude Code terminal to confirm parity is preserved
- plain shell command input to confirm no regression

### Test coverage
- Add focused tests for the compose submission helper if factored into a model/session seam.
- If direct UI automation is not practical, test the submit-routing logic at the smallest stable boundary.

## Risks
- Codex may treat pasted text differently from typed text, especially around multiline prompts.
- Separate PTY writes for payload and submit may not behave identically across agent CLIs.
- Fixing only one compose surface will leave inconsistent UX, so all send paths must be consolidated.

## UI impact

Low visual impact, high workflow impact. No new UI required. This is primarily a behavior and consistency fix.
