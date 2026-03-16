# API Locker — Design Spec

**Date:** 2026-03-16
**Status:** Approved

## Overview

A global, PIN-gated vault for storing API keys securely in TermGrid. Uses macOS Keychain for secret storage and a JSON file for display metadata. Keys are injected as environment variables into all terminal PTY sessions when the vault is unlocked. The locker is accessed via a toolbar lock icon that toggles a right-side inspector panel.

## 1. Architecture

### Storage — Two Layers

**Secrets (macOS Keychain):**
- Each API key stored as `kSecClassGenericPassword`
- Service: `com.termgrid.api-locker`
- Account: entry UUID (unique identifier per key)
- Value: raw API key string as UTF-8 data
- Keychain handles encryption via the Secure Enclave / OS-level protection

**Metadata (`~/.termgrid/api-locker/metadata.json`):**
```json
{
  "pinHash": "pbkdf2-derived-hex-string",
  "pinSalt": "random-16-byte-hex-string",
  "entries": [
    {
      "id": "uuid-string",
      "name": "OpenAI",
      "brandColor": "#10A37F",
      "docsURL": "https://platform.openai.com/docs",
      "envVarName": "OPENAI_API_KEY",
      "agentNotes": "Use for GPT-4 and embeddings. Rate limit: 10k RPM.",
      "createdAt": "2026-03-16T12:00:00Z"
    }
  ]
}
```

No secrets in the JSON file (except `maskedKey` — last 4 chars, accepted tradeoff). Only display metadata, agent context, and the hashed PIN.

### In-Memory State

When unlocked, all keys are read from Keychain into an in-memory `[String: String]` dictionary (envVarName → rawKey). This dictionary is:
- Passed to `TerminalSessionManager` for PTY env injection
- Cleared on lock or app termination
- Never written to disk outside of Keychain

## 2. PIN System

**PIN format:** 4–6 numeric digits.

**Storage:** PBKDF2-derived hash of the PIN stored in `metadata.json` (`pinHash` and `pinSalt` fields). Uses 100,000 iterations with a random 16-byte salt to resist brute-force (a 4-6 digit PIN has only ~1M possible values).

**Verification flow:**
1. User enters PIN
2. App derives key using PBKDF2 with stored salt and 100,000 iterations
3. Compares against stored `pinHash`
4. If match: read all keys from Keychain into memory, transition to unlocked state
5. If mismatch: show error, stay locked

**First-time setup:** If no `metadata.json` exists (or `pinHash` is empty), show "Set PIN" mode instead of "Unlock" mode.

**PIN is a gate, not an encryption key.** Keychain encryption is handled by the OS, tied to the macOS user account. The PIN prevents casual access within TermGrid.

## 3. Auto-Lock

**Timeout:** 15 minutes (900 seconds) of inactivity.

**Timer behavior:**
- Starts when vault is unlocked
- Resets on any vault action (add key, copy key, reveal key, edit metadata)
- Does NOT reset on unrelated app actions (typing in terminal, switching cells)
- When timer hits zero: clear in-memory keys, UI returns to locked state

**Display:** MM:SS countdown in the unlocked panel header. Text turns `Theme.accent` when under 60 seconds to warn the user.

**Note:** Existing terminal sessions keep their injected env vars after lock (standard Unix behavior — env is copied at process spawn). Only new sessions spawned after lock will lack the keys.

## 4. UI — Toolbar Integration

**Lock icon in main toolbar** (next to the existing `GridPickerView` toolbar item).

**Icon states:**
- Locked: `lock.fill` in `Theme.headerIcon` (#7A756B)
- Unlocked: `lock.open.fill` in `Theme.accent` (#C4A574) — draws attention to active state

**Action:** Toggles the inspector panel open/closed.

**Implementation:** Add a `@State private var showAPILocker = false` to `TermGridApp`. Use `.inspector(isPresented:)` modifier if it works in the plain `Window` scene context (macOS 14+). **Fallback:** If `.inspector()` requires `NavigationSplitView` (which TermGrid does not use), implement the panel as an `HStack` trailing panel with slide animation — same visual result, no navigation dependency. The toolbar button itself should be added to the existing toolbar in `ContentView.swift` alongside `GridPickerView`.

## 5. UI — Inspector Panel (Locked State)

**Panel width:** 280pt, right side of window.

**Layout (centered vertically):**
```
┌──────────────────────────────┐
│                              │
│        🔒 (large icon)       │
│                              │
│        API Locker            │
│   Enter PIN to unlock keys   │
│                              │
│     ● ● ● ● ○ ○            │
│         👁 Show PIN          │
│                              │
│       [ Unlock ]             │
│                              │
│   ⚠️ Wrong PIN (if error)    │
│                              │
└──────────────────────────────┘
```

- Lock icon: SF Symbol `lock.rectangle.fill`, 48pt, `Theme.accent` color
- Title: "API Locker" — `.system(size: 16, weight: .semibold)`, `Theme.headerText`
- Subtitle: "Enter PIN to unlock keys" — `.system(size: 12)`, `Theme.headerIcon`
- PIN circles: HStack of 4–6 circles. Empty = stroke `Theme.headerIcon`, filled = `Theme.accent`
- Eye toggle: `eye.slash` / `eye` — toggles between dots and digits
- Unlock button: Accent-colored, rounded rect
- Error message: Red text, appears below button on wrong PIN

**First-time setup mode:** Same layout but title says "Set a PIN", button says "Set PIN", and there's a confirm PIN field.

## 6. UI — Inspector Panel (Unlocked State)

**Layout:**
```
┌──────────────────────────────┐
│ API Locker        ⏱ 14:32   │
├──────────────────────────────┤
│ ┌──────────────────────────┐ │
│ │█ OpenAI                  │ │
│ │  ****8X9Z     📋 👁 🗑  │ │
│ │  OPENAI_API_KEY          │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │█ Anthropic               │ │
│ │  ****4mNp     📋 👁 🗑  │ │
│ │  ANTHROPIC_API_KEY       │ │
│ └──────────────────────────┘ │
│                              │
│ ┌ Add API Key ─────────────┐ │
│ │ Name: [          ]       │ │
│ │ Key:  [••••••••••]       │ │
│ │ Env:  [OPENAI_API_KEY]   │ │
│ │ Docs: [https://...]      │ │
│ │ Color: [● picker]        │ │
│ │ Notes: [agent context..] │ │
│ │        [ Add Key ]       │ │
│ └──────────────────────────┘ │
│                              │
│       [ 🔒 Lock Vault ]     │
└──────────────────────────────┘
```

### Key Cards

Each card is a rounded rect with:
- **Left color stripe:** 4pt wide, full height, service brand color
- **Background:** `Theme.cellBackground` (#232328) with subtle border `Theme.cellBorder`
- **Service name:** `.system(size: 13, weight: .semibold)`, `Theme.headerText`
- **Masked key:** `.system(size: 11, design: .monospaced)`, `Theme.notesSecondary` — shows `****` + last 4 chars
- **Env var name:** `.system(size: 10, design: .monospaced)`, `Theme.composePlaceholder` — shows the environment variable name
- **Action buttons (trailing):**
  - `doc.on.doc` — copy raw key to clipboard (resets auto-lock timer)
  - `eye` / `eye.slash` — toggle full key reveal
  - `trash` — delete (with confirmation alert)

### Service Brand Colors (built-in presets)

| Service | Color |
|---------|-------|
| OpenAI | #10A37F |
| Anthropic | #D4A574 |
| Stripe | #635BFF |
| Google | #4285F4 |
| AWS | #FF9900 |
| Azure | #0078D4 |
| GitHub | #8B5CF6 |
| Cloudflare | #F6821F |
| Custom | User-picked via color well |

**Auto-detection:** When the user types a service name, auto-suggest the matching brand color. Fall back to custom picker.

### Add Key Form

- **Name:** TextField — service name (e.g. "OpenAI Production")
- **Key:** SecureField — the actual API key
- **Env Var:** TextField — environment variable name (e.g. `OPENAI_API_KEY`). Auto-suggested from name: uppercase + `_API_KEY` suffix
- **Docs URL:** TextField (optional) — link to API documentation
- **Color:** Small color well with preset swatches + custom picker
- **Agent Notes:** TextEditor (optional, 2–3 lines) — context for AI agents (rate limits, usage notes, etc.)
- **Add Key button:** Accent-colored, validates: name + key non-empty, `envVarName` unique across existing entries (show inline error if duplicate)

### Auto-Lock Countdown

- Position: top-right of panel header
- Format: `⏱ MM:SS`
- Font: `.system(size: 11, design: .monospaced)`
- Color: `Theme.notesSecondary` normally, `Theme.accent` under 60 seconds
- Resets on: add key, copy key, reveal key, edit entry, delete entry

## 7. PTY Environment Injection

**When vault is unlocked:**
- `APIKeyVault` holds `decryptedKeys: [String: String]` mapping env var names to raw keys
- `TerminalSessionManager.createSession(for:workingDirectory:)` reads this dictionary
- Keys are merged into the shell process environment at spawn time
- Each key becomes an env var: e.g. `OPENAI_API_KEY=sk-proj-xxx`

**When vault is locked:**
- `decryptedKeys` is cleared (empty dictionary)
- New terminal sessions get no API keys in their environment
- Existing sessions retain their env (already spawned — OS behavior)

**Implementation:**

SwiftTerm's `startProcess(environment:)` takes `[String]?` — an array of `"KEY=VALUE"` strings, NOT a dictionary. When `nil` is passed (current behavior), SwiftTerm uses its own minimal set (TERM, COLORTERM, LANG, etc.).

`TerminalSession.init` must accept an optional environment parameter:

```swift
init(cellID: UUID, workingDirectory: String, environment: [String]? = nil) {
    // ... existing setup ...
    terminalView.startProcess(
        executable: shell,
        args: ["-l"],
        environment: environment,  // was nil
        execName: nil,
        currentDirectory: workingDirectory
    )
}
```

`TerminalSessionManager` builds the env array from vault keys and passes it:

```swift
func createSession(for cellID: UUID, workingDirectory: String) -> TerminalSession {
    // ... existing kill logic ...
    let env = buildEnvironment()
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory, environment: env)
    sessions[cellID] = session
    return session
}

private func buildEnvironment() -> [String]? {
    guard !vaultKeys.isEmpty else { return nil } // nil = SwiftTerm default
    // Start with SwiftTerm's default env, then append vault keys
    var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
    for (key, value) in vaultKeys {
        env.append("\(key)=\(value)")
    }
    return env
}
```

Both `createSession` and `createSplitSession` must use this same pattern — all terminal spawns get vault keys.

## 8. Data Model

```swift
struct APIKeyEntry: Codable, Identifiable {
    let id: UUID
    var name: String
    var envVarName: String
    var brandColor: String       // hex string
    var docsURL: String?         // optional link to API docs
    var agentNotes: String?      // optional context for AI agents
    var createdAt: Date
    var maskedKey: String        // last 4 chars, computed on save
}
// Note: maskedKey leaks 4 chars of the key to disk. This is an accepted tradeoff —
// 4 chars cannot reconstruct a key, and it avoids Keychain reads for every UI render.

struct APILockerMetadata: Codable {
    var pinHash: String          // PBKDF2-derived hex
    var pinSalt: String          // random 16-byte salt as hex
    var entries: [APIKeyEntry]
}
```

**Persistence directory:** `~/Library/Application Support/TermGrid/api-locker/` (consistent with existing `PersistenceManager` pattern)
**Metadata file:** `~/Library/Application Support/TermGrid/api-locker/metadata.json`

## 9. State Management

```swift
enum LockerState {
    case locked
    case unlocked(expiresAt: Date)
    case noVault                  // first-time: no PIN set yet
}
```

`APIKeyVault` is `@MainActor @Observable`:
- `state: LockerState`
- `decryptedKeys: [String: String]` — only populated when unlocked
- `entries: [APIKeyEntry]` — always available (metadata, no secrets)
- Methods: `setPIN(_:)`, `unlock(pin:)`, `lock()`, `addKey(...)`, `removeKey(id:)`, `copyKey(id:)`, `revealKey(id:) -> String?`

Owned by `TermGridApp` as `@State`, passed down to toolbar + inspector panel.

## 10. New Files

| File | Purpose |
|------|---------|
| `Sources/TermGrid/APILocker/APIKeyVault.swift` | Keychain CRUD, PIN hashing, in-memory key cache, auto-lock timer |
| `Sources/TermGrid/APILocker/APILockerMetadata.swift` | `APIKeyEntry` and `APILockerMetadata` Codable models, JSON persistence |
| `Sources/TermGrid/APILocker/APILockerPanel.swift` | Inspector panel — locked/unlocked states, key list, add form |
| `Sources/TermGrid/APILocker/APIKeyCard.swift` | Individual key card view with color stripe + actions |
| `Tests/TermGridTests/APIKeyVaultTests.swift` | Vault logic tests (PIN hash, add/remove, state transitions) |
| `Tests/TermGridTests/APILockerMetadataTests.swift` | Metadata model encoding/decoding tests |

## 11. Files Modified

| File | Changes |
|------|---------|
| `TermGridApp.swift` | Add vault state, pass to ContentView |
| `TerminalSession.swift` | Accept optional `environment: [String]?` parameter in init |
| `TerminalSessionManager.swift` | Accept vault reference, build env array, inject into both `createSession` and `createSplitSession` |
| `ContentView.swift` | Add toolbar lock button, locker panel (inspector or HStack fallback), pass vault to session manager |

## 12. Security Considerations

- Raw keys NEVER written to disk outside Keychain
- Raw keys NEVER in SwiftUI view state — only in `APIKeyVault.decryptedKeys` (model layer)
- Masked keys (last 4 chars) stored in metadata for UI display
- Reveal action reads from Keychain on demand, result not cached in view
- `metadata.json` contains NO secrets — safe to back up
- Auto-lock clears in-memory keys after 15 minutes
- App termination clears in-memory keys (standard process exit)
- Assumes non-sandboxed execution (Keychain access without entitlements)
- **Keychain error handling:** All Keychain operations (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`) return `OSStatus`. On failure, show an alert with the error description. Common failures: keychain locked after sleep (re-prompt PIN), access denied (show instructions), item already exists on add (update instead). V1 approach: catch errors and show user-facing alert, do not silently swallow.

## 13. Out of Scope (V1)

- Touch ID / biometric unlock (can add in V2 via LocalAuthentication)
- PIN change (must delete vault and re-create in V1)
- Key import/export
- Per-cell key selection (all keys injected into all terminals)
- CLI tool for agent access (could add `termgrid-keys` CLI in V2, similar to King Conch's `conch-keys`)
- Encrypted metadata file (only secrets need encryption — Keychain handles those)
- Key rotation / expiry tracking
