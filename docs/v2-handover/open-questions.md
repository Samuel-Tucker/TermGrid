# Open Questions — Resume Brainstorming Here

## Question 1: Communication Channel (NEXT)

Hook scripts (shell commands triggered by Claude Code / Codex) run as separate processes outside TermGrid. They need to send the agent's message to the running TermGrid app so it can fire a macOS notification.

**Options presented to Sam (not yet chosen):**

### A) Unix Domain Socket
- TermGrid listens on `~/.termgrid/notify.sock`
- Hook script writes JSON to socket
- **Pros:** Fast, local-only, no port conflicts, reliable
- **Cons:** Slightly more code to implement, need to handle socket lifecycle

### B) Local HTTP Server
- TermGrid runs tiny HTTP server on `localhost:<port>`
- Hook script does `curl -X POST localhost:<port>/notify -d '...'`
- **Pros:** Dead simple to debug (`curl` from terminal), easy to test
- **Cons:** Port conflicts possible, technically network-accessible (localhost only but still)

### C) NSDistributedNotificationCenter
- Hook script posts a macOS distributed notification
- TermGrid observes it
- **Pros:** No server, no socket, native macOS IPC
- **Cons:** Payload size limited (~4KB), less reliable for large messages, any app can observe

**Recommendation to present:** Option A (Unix domain socket) is most robust. But ask Sam — he may prefer B for debuggability.

## Question 2: Message Truncation

macOS notification banners have limited visible text (~4 lines). Agent messages can be very long. How should we truncate?

**Options to explore:**
- Show last N characters of the agent's message
- Show a summary line + "expand for full message"
- Show the agent's final question/statement only (parse from transcript)

## Question 3: Multiple Pending Notifications

What happens if 3 agents all finish while user is in email?

**Options to explore:**
- Stack notifications (macOS groups them by app in Notification Center)
- Each gets its own banner with cell label identifier
- Priority ordering (needs_input > complete)

## Question 4: Codex approval-requested Gap

Codex's `approval-requested` event doesn't trigger the external `notify` hook (only TUI notifications as of March 2026). This means we can detect when Codex *finishes* but not when it *needs permission*.

**Options to explore:**
- Wait for OpenAI to add it (tracked: github.com/openai/codex/issues/11808)
- Poll Codex TUI state as workaround
- Accept the limitation for now, document it

## Question 5: Session Identification in Hooks

When a hook fires, we need to know WHICH TermGrid cell/terminal it belongs to. The hook runs in the working directory of the agent.

**Approach to explore:**
- TermGrid writes a `.termgrid-session` file to each cell's working directory containing `{ cellID, sessionID }`
- Hook script reads this file and includes it in the notification payload
- This maps the notification back to the correct PTY for reply routing
