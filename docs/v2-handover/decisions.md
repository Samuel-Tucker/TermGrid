# V2 Design Decisions

All decisions made during brainstorming with Sam. These are final unless Sam changes them.

## 1. Target Agents: Claude Code + Codex Only

**Decision:** Only support Claude Code and OpenAI Codex CLI. No Gemini, no Aider, no generic agents.

**Why:** "Focus on Claude Code and Codex, get them mega reliable. I don't care if it takes months, work slowly, make sure we take the right approach."

**Implication:** No heuristic detection, no generic terminal output parsing. Use each agent's native hook/notification system. Two rock-solid integrations beats ten flaky ones.

## 2. Detection Mechanism: Native Hooks

**Decision:** Use Claude Code hooks system and Codex CLI `notify` config. Not the COP/OSC 7770 protocol from King Conch.

**Why:** Both agents have official hook systems that fire on completion/input-needed events. This is cleaner than parsing terminal output.

**Claude Code hooks used:**
- `Stop` — fires when Claude finishes responding
- `Notification` — fires on `permission_prompt`, `idle_prompt`, `elicitation_dialog`

**Codex hooks used:**
- `notify` — fires on `agent-turn-complete`
- `approval-requested` — exists as TUI event but does NOT trigger external notify hook yet (as of March 2026)

## 3. Notification UX: Inline Reply (iMessage Pattern)

**Decision:** Every notification (both `complete` and `needs_input`) gets:
- The agent's actual message as the notification body (for context)
- An inline text reply action (type your response in the banner)
- A dismiss button

**Why for complete having reply:** "Complete might be 'I'm done, shall I do next slice?' — therefore we need ability to say 'yes do next slice', equally we need a dismiss button too in case they want to get rid of it for now."

**macOS API:** `UNTextInputNotificationAction` — exactly how iMessage inline reply works. Limited to 2 actions per banner (Reply + Dismiss is perfect).

## 4. Never Navigate Away

**Decision:** Clicking the notification MUST NOT open TermGrid or switch focus to it. The user deals with the notification entirely within the banner/popup.

**Why:** "You will set your agents running and go and do emails etc. You don't want to check back and going back to that workspace breaks your flow."

This means:
- No `UNNotificationDefaultActionIdentifier` handler that opens the app
- The notification category must be configured so tapping the banner expands it for reply, not opens the app
- If the user explicitly wants to go to TermGrid, they click the dock icon themselves

## 5. Response Routing

**Decision:** When user replies in the notification, the text must be piped back to the correct terminal's PTY via `TerminalSession.send()`.

**Implication:** The notification must carry metadata identifying which cell/session it belongs to. The notification delegate must be able to route the response to the right `TerminalSession`.
