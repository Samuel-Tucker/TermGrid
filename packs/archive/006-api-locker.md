# Pack 006: API Locker

**Type:** Feature
**Status:** Complete
**Date:** 2026-03-17

## Summary

PIN-gated API key vault integrated into TermGrid. Stores API keys securely in macOS Keychain, displays them in a right-side inspector panel with service brand colors, and injects them as environment variables into all terminal sessions when unlocked.

## Features

### Vault
- 4-6 digit numeric PIN with HKDF-derived hash + random salt (not plain SHA-256)
- macOS Keychain for secret storage (OS-level encryption)
- JSON metadata file for display data (service names, colors, docs URLs, agent notes)
- Persistence in `~/Library/Application Support/TermGrid/api-locker/`
- Auto-lock after 15 minutes with visible countdown
- In-memory key cache cleared on lock/app exit

### UI
- Lock icon in toolbar (lock.fill when locked, lock.open.fill when unlocked in accent color)
- Right-side inspector panel slides in/out
- Three states: Set PIN (first time), Locked (enter PIN), Unlocked (key management)
- Key cards with left brand color stripe, masked key (last 4 chars), env var name
- Copy/reveal/delete actions per key
- Add key form with auto-suggested env var name and brand color detection
- 8 preset brand colors (OpenAI, Anthropic, Stripe, Google, AWS, Azure, GitHub, Cloudflare)

### Terminal Integration
- When unlocked, all keys injected as env vars into new terminal sessions
- Both main and split terminal sessions receive keys
- Existing sessions retain env after lock (Unix process behavior)

## Files Created
- `Sources/TermGrid/APILocker/APILockerMetadata.swift`
- `Sources/TermGrid/APILocker/APIKeyVault.swift`
- `Sources/TermGrid/APILocker/APIKeyCard.swift`
- `Sources/TermGrid/APILocker/APILockerPanel.swift`
- `Tests/TermGridTests/APILockerMetadataTests.swift`
- `Tests/TermGridTests/APIKeyVaultTests.swift`

## Files Modified
- `Sources/TermGrid/TermGridApp.swift`
- `Sources/TermGrid/Views/ContentView.swift`
- `Sources/TermGrid/Terminal/TerminalSession.swift`
- `Sources/TermGrid/Terminal/TerminalSessionManager.swift`

## Testing
- 69 tests total (16 new for API Locker)
- Covers: metadata encoding, PIN hashing, vault state transitions, key CRUD, duplicate env var rejection
