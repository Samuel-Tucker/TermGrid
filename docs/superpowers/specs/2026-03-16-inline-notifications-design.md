# TermGrid V2 — Inline Notification System Design

## Objective

Add iMessage-style inline notifications to TermGrid so that when AI coding agents (Claude Code or Codex CLI) finish a task or need user input, a macOS native notification appears. The user replies directly inside the notification banner without switching apps. The reply pipes back to the correct terminal's PTY.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Target agents | Claude Code + Codex CLI only | Two rock-solid integrations beats ten flaky ones |
| Detection | Native hooks (no heuristics) | Both agents have official hook systems |
| Communication channel | Unix domain socket (`~/.termgrid/notify.sock`) | No port conflicts, no network exposure, no payload limits |
| Session identification | `TERMGRID_CELL_ID` + `TERMGRID_SESSION_TYPE` env vars | No files to manage, handles two-cells-same-directory edge case |
| Message display | Extract final question/statement for banner; full message in body for expansion | macOS handles truncation/expansion natively, no extension target needed |
| Multiple notifications | Stack individually, grouped per cell via `threadIdentifier` | Simple, proven (iMessage pattern) |
| Codex approval-requested gap | Accept limitation; recommend full-auto permissions | Hooks only, no workarounds. OpenAI tracking the issue |
| Notification tap behavior | Never activates TermGrid | `.customDismissAction` + no-op default action handler |
| Notification content | Title = cell label, Subtitle = terminal label, Body = summary + full message | Three-tier context: project, agent, message |

## Component Architecture

```
Sources/TermGrid/
├── Notifications/
│   ├── AgentSignal.swift          — Signal model + enums
│   ├── SocketServer.swift         — Unix domain socket listener
│   ├── NotificationManager.swift  — UNNotification lifecycle + delegate + reply routing
│   └── MessageParser.swift        — Extract summary from agent messages
├── Terminal/
│   └── TerminalSession.swift      — Modified: inject env vars on PTY spawn
└── TermGridApp.swift              — Modified: wire notification subsystem on launch
```

### AgentSignal

```swift
struct AgentSignal {
    let cellID: UUID
    let sessionType: SessionType   // .primary or .split
    let agentType: AgentType       // .claudeCode or .codex
    let eventType: EventType       // .complete or .needsInput
    let fullMessage: String
    let summary: String
}

enum SessionType: String, Codable { case primary, split }
enum AgentType: String, Codable { case claudeCode, codex }
enum EventType: String, Codable { case complete, needsInput }
```

### SocketServer

Runs on a background `DispatchQueue`:

1. Remove stale `~/.termgrid/notify.sock` if it exists (previous crash)
2. Create Unix domain socket, bind, listen
3. Accept connections in a loop, read until newline delimiter
4. Parse JSON into intermediate struct, dispatch to `@MainActor` for NotificationManager
5. On app quit, close socket and remove file

### NotificationManager

Created in `TermGridApp.init()` with injected references to `WorkspaceStore` and `TerminalSessionManager` (same instances the UI uses).

**On startup:**
1. Request notification permission (`UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])`)
2. Register notification category `AGENT_MESSAGE` with:
   - `UNTextInputNotificationAction` — identifier `REPLY_ACTION`, button "Send", placeholder "Type your response..."
   - `UNNotificationAction` — identifier `DISMISS_ACTION`, title "Dismiss"
   - Category option: `.customDismissAction`
3. Set self as `UNUserNotificationCenter` delegate

**When AgentSignal arrives:**
1. Look up `Cell` from `WorkspaceStore` by `cellID` for labels
2. Fire notification:
   - `title` = cell label (e.g. "My Feature Work")
   - `subtitle` = terminal label (e.g. "Opus — UI Fix")
   - `body` = summary + "\n\n" + full message
   - `categoryIdentifier` = `"AGENT_MESSAGE"`
   - `userInfo` = `["cellID": uuid, "sessionType": "primary"|"split"]`
   - `threadIdentifier` = cellID string
   - `trigger` = nil (immediate)

**When user replies:**
1. Cast response to `UNTextInputNotificationResponse`, get `userText`
2. Extract `cellID` and `sessionType` from `userInfo`
3. Dispatch to `@MainActor`
4. Look up session: primary → `manager.session(for:)`, split → `manager.splitSession(for:)`
5. If session found and running: `session.send(userText + "\r")`
6. If session nil: fire follow-up notification "Session no longer active — reply could not be delivered"

**Default action handler:** No-op. Never activates TermGrid.

### MessageParser

Two static methods:

- `parseClaudeCodeMessage(transcriptPath:)` — reads JSONL transcript, finds last assistant message, extracts final question/statement
- `parseCodexMessage(lastAssistantMessage:)` — takes Codex direct field, extracts final question/statement

Extraction logic: scan backwards for a sentence ending with `?`, fall back to last sentence. Simple string processing.

## Wire Protocol

Hook scripts write a single JSON line to the Unix socket:

```json
{
  "cellID": "uuid-string",
  "sessionType": "primary",
  "agentType": "claudeCode",
  "eventType": "needsInput",
  "message": "full agent message text"
}
```

Claude Code hooks: script reads hook payload from stdin, extracts transcript path, reads last assistant message from JSONL, writes to socket.

Codex hooks: script reads `last-assistant-message` from JSON argument, writes to socket.

Both scripts read `$TERMGRID_CELL_ID` and `$TERMGRID_SESSION_TYPE` from environment.

## Hook Scripts

### `~/.termgrid/hooks/termgrid-notify-claude.sh`

```bash
#!/bin/bash
PAYLOAD=$(cat)
TRANSCRIPT=$(echo "$PAYLOAD" | jq -r '.transcript_path')
EVENT=$(echo "$PAYLOAD" | jq -r '.hook_event_name')

MESSAGE=$(tail -20 "$TRANSCRIPT" | jq -sr '[.[] | select(.type=="assistant")] | last | .message.content // ""')

if [ "$EVENT" = "Stop" ]; then EVENT_TYPE="complete"; else EVENT_TYPE="needsInput"; fi

echo "{\"cellID\":\"$TERMGRID_CELL_ID\",\"sessionType\":\"$TERMGRID_SESSION_TYPE\",\"agentType\":\"claudeCode\",\"eventType\":\"$EVENT_TYPE\",\"message\":$(echo "$MESSAGE" | jq -Rs .)}" | socat - UNIX-CONNECT:~/.termgrid/notify.sock

echo '{"decision":"approve","reason":"Notification sent"}'
```

### `~/.termgrid/hooks/termgrid-notify-codex.sh`

```bash
#!/bin/bash
PAYLOAD="$1"
MESSAGE=$(echo "$PAYLOAD" | jq -r '.["last-assistant-message"] // ""')

echo "{\"cellID\":\"$TERMGRID_CELL_ID\",\"sessionType\":\"$TERMGRID_SESSION_TYPE\",\"agentType\":\"codex\",\"eventType\":\"complete\",\"message\":$(echo "$MESSAGE" | jq -Rs .)}" | socat - UNIX-CONNECT:~/.termgrid/notify.sock
```

**External dependency:** `socat` (available via `brew install socat`).

## Terminal Session Modification

When spawning the PTY process in `TerminalSession`, inject env vars by merging with system environment:

```swift
var env = ProcessInfo.processInfo.environment
env["TERMGRID_CELL_ID"] = cellID.uuidString
env["TERMGRID_SESSION_TYPE"] = sessionType.rawValue  // "primary" or "split"
// Pass merged env to SwiftTerm process launch
```

This preserves PATH and all existing environment variables.

## Hook Installation & Setup

**On launch:** TermGrid writes/updates hook scripts to `~/.termgrid/hooks/` with `chmod +x`. A version marker (`~/.termgrid/hooks/.version`) tracks whether scripts need updating.

**User-facing setup:** A "Setup Agent Hooks" button in toolbar or first-run prompt:

- **Claude Code:** Merges hook entries into `~/.claude/settings.json` (preserving existing config)
- **Codex CLI:** Merges `[notify]` section into `~/.codex/config.toml` (preserving existing config)

**Recommended permissions guidance:** Setup flow shows:
> "For best results, run Claude Code with bypass permissions mode, and Codex with --full-auto. This ensures every agent stop is a genuine completion or question."

**socat check:** Setup verifies `socat` is installed, shows install instructions if not.

## Testing Strategy

### Unit Tests

**MessageParserTests:**
- Extract question from message ending with `?`
- Extract last sentence when no question present
- Handle multi-paragraph, single-word, empty messages
- Parse Claude Code JSONL transcript
- Parse Codex direct field

**AgentSignalTests:**
- Decode valid JSON payload
- Handle missing/unknown fields gracefully
- Round-trip encode/decode

**SocketServerTests:**
- Creates socket file at expected path
- Removes stale socket on start
- Accepts connection and reads JSON line
- Handles multiple concurrent connections
- Cleans up socket file on stop
- Handles malformed JSON without crashing

**NotificationManagerTests:**
- Category registered with correct actions
- Fires notification with correct title/subtitle/body
- Reply routes to correct session (primary and split)
- Reply to nonexistent session fires follow-up
- Dismiss action calls completion handler without side effects

### Integration Test (Manual)

```bash
echo '{"cellID":"<uuid>","sessionType":"primary","agentType":"claudeCode","eventType":"complete","message":"Tests pass. Shall I continue?"}' | socat - UNIX-CONNECT:~/.termgrid/notify.sock
```

Verify notification appears, reply routes to terminal.

### V1 Regression

All 30 existing tests must continue passing. Only V1 modification is env var injection in `TerminalSession.swift` — additive change, existing tests unaffected.

## Implementation Sequence

1. Create `AgentSignal` model
2. Implement `MessageParser` (independently testable)
3. Implement `SocketServer` (testable with socat)
4. Implement `NotificationManager` (registration, firing, delegate, reply routing)
5. Modify `TerminalSession` to inject `TERMGRID_CELL_ID` + `TERMGRID_SESSION_TYPE`
6. Modify `TermGridApp` to wire subsystem on launch
7. Create hook scripts
8. Implement hook installation/setup UI
9. Write tests
10. Manual integration testing with real Claude Code/Codex hooks

## Codex Review

Design cross-checked via Codex 5.3 multi-agent review. Five critical blind spots identified and resolved:

1. Added `TERMGRID_SESSION_TYPE` for split terminal routing
2. Moved NotificationManager creation to `TermGridApp.init()` with dependency injection
3. Environment variable merge strategy (preserve system env)
4. Dropped `UNNotificationContentExtension` — use native body expansion instead
5. Added hook registration/deployment steps

## Constraints / Non-Goals

- Do NOT break V1 functionality
- Do NOT support agents beyond Claude Code and Codex CLI
- Do NOT use heuristic/output-parsing detection
- Do NOT use COP/OSC 7770 protocol from King Conch
- Do NOT navigate to TermGrid when notification is tapped
- No SwiftNIO — use Foundation/Darwin sockets directly
