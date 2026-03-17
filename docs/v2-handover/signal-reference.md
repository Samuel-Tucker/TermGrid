# Agent Signal Reference

> **Note:** This document was initial research. The design spec at `docs/superpowers/specs/2026-03-16-inline-notifications-design.md` supersedes it. Key differences: Stop hooks include `last_assistant_message` directly (no transcript parsing needed), Notification hooks include `message`/`notification_type` fields, and hook scripts should exit 0 with no stdout JSON.

Exact payloads and configuration for Claude Code and Codex CLI hooks.

## Claude Code

### Hook Configuration

Hooks are defined in `.claude/settings.json` or per-project `.claude/settings.local.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/termgrid-notify.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/termgrid-notify.sh"
          }
        ]
      }
    ]
  }
}
```

### Stop Hook — Stdin Payload

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/dir",
  "permission_mode": "ask",
  "hook_event_name": "Stop",
  "stop_hook_reason": "end_turn"
}
```

**To get the agent's last message:** Read `transcript_path` (JSONL file), find the last assistant message. This is what shows in the notification body.

### Notification Hook — Stdin Payload

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/dir",
  "permission_mode": "ask",
  "hook_event_name": "Notification"
}
```

**Event subtypes** (determined by context, not explicitly in payload):
- `permission_prompt` — Claude needs permission to run a tool
- `idle_prompt` — Claude is waiting for user input
- `elicitation_dialog` — Claude is prompting the user with a question

### Hook Output Format

```json
{
  "decision": "approve",
  "reason": "Notification sent to TermGrid"
}
```

Exit code 0 = approve (let Claude continue). The hook script should always approve — it's just forwarding the notification, not blocking.

## Codex CLI

### Notify Configuration

In `~/.codex/config.toml`:

```toml
[notify]
command = "/path/to/termgrid-notify-codex.sh"
```

Or per-invocation: `codex --notify "/path/to/termgrid-notify-codex.sh"`

### Notify Payload (JSON argument)

```json
{
  "type": "agent-turn-complete",
  "thread-id": "thread_abc123",
  "turn-id": "turn_xyz789",
  "cwd": "/current/working/dir",
  "input-messages": ["user message that started this turn"],
  "last-assistant-message": "I've completed the refactoring. The tests pass. Shall I move on to the next task?"
}
```

**Key difference from Claude Code:** Codex gives you `last-assistant-message` directly. No need to read a transcript file.

### Known Limitations (March 2026)

- `approval-requested` event exists but does NOT trigger the external `notify` hook
- Only `agent-turn-complete` fires the external hook
- Tracked: https://github.com/openai/codex/issues/11808
- TUI notifications (`[tui].notifications = ["agent-turn-complete", "approval-requested"]`) work for both events but only within the Codex terminal UI — not useful for TermGrid

## macOS Notification API

### UNTextInputNotificationAction

```swift
import UserNotifications

// Create the reply action
let replyAction = UNTextInputNotificationAction(
    identifier: "REPLY_ACTION",
    title: "Reply",
    options: [],
    textInputButtonTitle: "Send",
    textInputPlaceholder: "Type your response..."
)

// Create dismiss action
let dismissAction = UNNotificationAction(
    identifier: "DISMISS_ACTION",
    title: "Dismiss",
    options: []
)

// Create category with both actions
let category = UNNotificationCategory(
    identifier: "AGENT_MESSAGE",
    actions: [replyAction, dismissAction],
    intentIdentifiers: [],
    options: []
)

// Register
UNUserNotificationCenter.current().setNotificationCategories([category])
```

### Firing a Notification

```swift
let content = UNMutableNotificationContent()
content.title = "Opus — UI Fix"  // cell label + terminal label
content.body = "I've completed the refactoring. Shall I move on to the next task?"
content.categoryIdentifier = "AGENT_MESSAGE"
content.userInfo = ["cellID": cellID.uuidString, "sessionType": "primary"]

let request = UNNotificationRequest(
    identifier: UUID().uuidString,
    content: content,
    trigger: nil  // fire immediately
)

UNUserNotificationCenter.current().add(request)
```

### Handling the Reply

```swift
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let textResponse = response as? UNTextInputNotificationResponse {
            let replyText = textResponse.userText
            let cellID = response.notification.request.content.userInfo["cellID"] as? String
            // Route replyText to the correct TerminalSession.send()
        }
        completionHandler()
    }
}
```

### Key Constraint

To prevent the notification from opening the app when tapped, configure the category with `.customDismissAction` and handle the default action to do nothing:

```swift
let category = UNNotificationCategory(
    identifier: "AGENT_MESSAGE",
    actions: [replyAction, dismissAction],
    intentIdentifiers: [],
    options: [.customDismissAction]
)
```

And in the delegate, ignore `UNNotificationDefaultActionIdentifier`.
