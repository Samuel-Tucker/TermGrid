# Pack 019: Notification System V2 — Research-Backed Improvements

**Type:** Feature Spec (Research Pack)
**Priority:** High
**Depends on:** Pack 013 (Agent Notifications)
**Research source:** Grok 4.20 multi-agent (16 agents, web search, 404K tokens analyzed)

## Problem

Pack 013 delivers basic agent notifications via macOS banners and a planned notification dot. But the system lacks in-app notification UI, smart message parsing, output pattern detection for non-agent terminals, and visual cell attention indicators. The inline reply text field also doesn't work without Developer ID signing.

## Research Findings

16 Grok agents researched iTerm2, Warp, Kitty, VS Code, Zed, JetBrains, Grafana/Datadog, macOS HIG, Claude Code hooks schema, and Unix socket IPC best practices. Full research output: `/tests/grok42/termgrid_research.md`.

## Improvement 1: Extend Hook Scripts for Structured Events

**Impact: Highest / Effort: Lowest**

Claude Code hooks receive rich JSON on stdin — `Notification` type with `permission_prompt`, `idle_prompt`, `auth_success`; `PostToolUse` after tool calls. Currently our hooks only emit `eventType` and `message`.

### Action items:
- Update `termgrid-notify-claude.sh` to extract structured fields from hook stdin JSON: `summary`, `needsInputType`, notification subtype
- Add `summary` and `detail` fields to `SocketPayload` wire protocol
- In `MessageParser`, use structured fields first, fall back to regex extraction
- Keyword scoring for questions: match `"Would you like me to"`, `"Approve"`, `"What should I"`, phrases ending in `?`
- Strip ANSI, limit summaries to ~100 chars

### Wire protocol extension:
```json
{
  "cellID": "uuid",
  "sessionType": "primary|split",
  "agentType": "claudeCode|codex",
  "eventType": "complete|needsInput|buildComplete|testFailed|error|prompt",
  "message": "full agent output",
  "summary": "extracted 1-liner (optional, hook-provided)",
  "detail": "structured subtype from hook JSON (optional)"
}
```

## Improvement 2: Per-Cell Visual Indicators

**Impact: High / Effort: Low**

### Visual states:
| State | SF Symbol | Color | Behavior |
|---|---|---|---|
| Agent finished/waiting | `questionmark.circle.fill` | `Theme.accent` (#C4A574) | Steady |
| Needs input | `exclamationmark.triangle.fill` | Orange | Pulsing |
| Build failed | `xmark.circle.fill` | `#E06C75` | Steady |
| Tests passed | `checkmark.circle.fill` | `#75BE95` | Fade after 5s |
| Error | `exclamationmark.circle.fill` | `#E06C75` | Steady |

### SwiftUI pattern:
```swift
.overlay(alignment: .topTrailing) {
    if let status = cell.notificationStatus {
        Image(systemName: status.sfSymbol)
            .font(.system(size: 10))
            .foregroundColor(status.color)
            .background(Circle().fill(.background).padding(-2))
            .padding(4)
            .accessibilityLabel(status.accessibilityLabel)
    }
}
```

### Rules:
- Badge clears when user **scrolls to bottom** of terminal (same as Pack 013 dot)
- Pair colors with SF Symbols for accessibility — never color-only
- Support `UIAccessibility.isReduceMotionEnabled` (no pulse if enabled)
- Priority ordering: error > attention > SSH (Pack 015) > success
- Route `AgentSignal` to `@Published var notificationStatus` per cellID on `WorkspaceStore`

## Improvement 3: Output Pattern Detection

**Impact: High / Effort: Medium**

Add a lightweight scanner to detect important events in PTY output for all terminals, not just agent sessions.

### Regex patterns (cache with `NSRegularExpression`):
```
Build success:  (?i)(build|compile|Finished|compilation).*?(succeeded|successful|done|100%|compiled successfully)
Test pass:      (?i)(\d+ tests? passed|All tests passed|0 failures|Tests? (?:passed|ok))
Test fail:      (?i)(\d+)\s+failed|FAIL\s
Error generic:  (?i)\b(fatal|failure|exception|crash|stack trace)\b|^\s*error:
Swift error:    .*\.swift:\d+:\d+:\s*error:
Interactive:    \[y/n\]|\[Y/N\]|\[yes/no\]|\bpassword:|\bsudo\b
```

### Implementation:
- Scan normalized text from SwiftTerm's `getLine()` buffer API (not raw bytes — avoids ANSI/spinner false positives)
- Scanner runs on last N lines after each output chunk
- On match → create `AgentSignal` with synthetic `eventType` and generated summary
- Make patterns configurable via `~/.termgrid/notifications.json`
- Combine with hooks: structured events take priority when available

### Removed from original Pack 013 (too many false positives):
Raw `PASS`, `ERROR`, `$`, `%` — confirmed by both Codex review and Grok research

## Improvement 4: In-App Notification Banners

**Impact: Medium / Effort: Medium**

Show non-intrusive banners inside the cell, removing dependency on macOS native notifications (which require signing for reply).

### Design (informed by VS Code/JetBrains/Warp patterns):
- Top overlay toast inside cell, auto-dismisses after 5s
- Shows summary text + event icon
- Tap to scroll to relevant output
- Optional: shared notification sidebar/panel (JetBrains-style) — defer to later pack

### Why this matters:
- Native macOS banners require Developer ID signing for inline reply
- In-app banners work with ad-hoc signing
- Users stay in TermGrid instead of interacting with Notification Center

## Improvement 5: Socket Reliability Hardening

**Impact: Medium / Effort: Low**

### Fixes:
- Use serial `DispatchQueue` or Swift actor for concurrent write handling from multiple cells
- Handle fragmented messages: read until `\n` reliably, buffer partial reads
- Set `SO_SNDBUF` via `setsockopt` if buffer fills under heavy load
- Stale socket cleanup: check PID file on launch, `unlink()` dead sockets (partially implemented already)
- Add basic logging for dropped/malformed messages

### Keep Unix sockets:
Research confirms Unix domain sockets outperform loopback TCP and are competitive with XPC for this use case. XPC adds complexity without benefit since hooks are bash-based. Switch to XPC only if TermGrid goes fully sandboxed.

## Implementation Order

1. **Structured hooks + wire protocol extension** (builds on existing HookInstaller)
2. **Per-cell visual indicators** (SwiftUI overlays, few dozen lines)
3. **Output pattern scanner** (5-8 regexes + buffer scan)
4. **In-app banners** (SwiftUI overlay toast)
5. **Socket hardening** (serial queue, fragment handling)

## Competitor Reference

| Feature | iTerm2 | Warp | Kitty | VS Code | TermGrid V3 (target) |
|---|---|---|---|---|---|
| Native notifications | ✓ (shell integration) | ✓ (long-running cmds) | ✓ (OSC 99) | ✓ (extensions) | ✓ (hooks) |
| In-app indicators | Tab badges/dots | Block highlights | Window title | Tab decorators | Cell dots + border glow |
| Pattern detection | Regex triggers | Cmd duration + errors | No | Extension-based | Regex scanner |
| Agent-aware | No | No | No | Partial (Copilot) | Yes (Claude + Codex hooks) |
| Reply from notification | No | No | No | No | Yes (PTY routing) |

TermGrid's agent-aware notification system with reply routing is unique — no competitor does this.

## UI Impact

Minimal additive changes to existing views:
- SF Symbol overlay on CellView (10 lines)
- Optional border tint modifier (5 lines)
- Toast overlay component (new, ~50 lines)
- Status enum + publisher on WorkspaceStore (~30 lines)
