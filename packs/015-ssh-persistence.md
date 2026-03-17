# Pack 015: SSH Session Persistence

**Type:** Feature Spec
**Priority:** Low
**Competitors:** Wave, WezTerm, Tabby

## Problem

SSH sessions drop on sleep, network changes, or app restart.

## Solution

V1 scope narrowed per Codex feedback: **SSH connect/disconnect + saved profiles + visible remote state.** Defer restart persistence until the session model is expanded.

### What V1 does:
1. Connect to SSH hosts from a cell
2. Save/load SSH profiles
3. Show visual indicator when a cell is running an SSH session
4. Detect disconnection and offer reconnect (via remote `tmux` reattach only — single strategy)

### What V1 does NOT do:
- Auto-reconnect on sleep/network change (too many failure paths)
- ControlMaster multiplexing (complicates things)
- Raw shell reconnect without tmux

### Cell model changes:
- Add to `Cell`: `sshProfileID: UUID?`, `sessionType: SessionType` (`.local` | `.ssh`), `lastRemoteCwd: String?`
- These are persisted (tolerant decode with defaults)

### SSH profile storage:
- `SSHProfile`: `id`, `name`, `host`, `port`, `user`, `identityFile`, `jumpHost?`
- Stored in `Application Support/TermGrid/ssh-profiles.json`
- Passwords NOT stored (SSH keys or agent only)

### UI fit:
- **Folder pill menu addition:** "Connect SSH..." option opens a sheet
- **Note:** This mixes local filesystem and remote connection semantics in one menu. Acceptable for V1, but consider separating into a dedicated SSH button if it feels wrong in practice.
- **Connection indicator:** Small `antenna.radiowaves.left.and.right` icon after the cell label (uses the same status area as Pack 013 notification dots — priority: error > attention > SSH > success)
- **Reconnection overlay:** Reuse the existing "Session ended" overlay pattern with "Disconnected — Reconnect" button
- **No reconnection banner** — Codex flagged conflict with TerminalLabelBar in split mode

### Implementation:
- **New session type:** `TerminalSession` needs to support SSH. Since it's hardwired to `LocalProcessTerminalView.startProcess`, V1 launches `ssh` as a local process (simplest path). Full SSH channel integration (SwiftTerm's `SSHIntegration`) deferred to V2.
- **API Locker keys are NOT auto-forwarded to SSH sessions** — document this limitation clearly. Users can manually export them on the remote host.

### SSH connect sheet:
- Host, Port (default 22), Username, Identity File (file picker), Jump Host (optional)
- "Save Profile" checkbox
- "Connect" button

### UI impact: Minimal — 1 menu item + indicator icon (shared status area)
