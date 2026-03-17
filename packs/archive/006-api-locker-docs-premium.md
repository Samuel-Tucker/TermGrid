# Pack 006: API Locker Docs & Premium

**Type:** Feature
**Status:** Complete
**Date:** 2026-03-17

## Summary

Added a premium-gated Docs tab to the API Locker with Jina Reader integration for fetching and structuring API documentation. Added custom hover tooltip to the toolbar lock button.

## Changes

### Toolbar Hover Tooltip
- Lock button shows "API Locker" label on hover (custom pill tooltip, replacing native `.help()`)

### Freemium Model
- `isPremium` flag on `APILockerMetadata` with backward-compatible custom decoder
- V1: development convenience flag in JSON; V2 will need signed token/server validation
- Free users see Docs tab with blurred preview + premium gate CTA

### Docs Tab (Premium)
- Segmented picker in unlocked panel: "Keys" | "Docs (N)"
- Progressive disclosure: `+ Add documentation` per key, up to 10 docs per key
- Doc rows: status dot (green/red/spinner) + title + URL + delete
- Click to expand inline markdown preview (monospace, scrollable, 200px max)
- Premium gate: blurred mockup + "Unlock with Premium — £10/year" (placeholder)

### Jina Reader Integration
- Branded as TermGrid's own service (no "Jina" in UI)
- BYOK: uses `JINA_API_KEY` from vault's decrypted keys
- Premium proxy: placeholder branch for future server-side fetching
- URL validation: https/http only, rejects file:// and javascript:
- 2MB response truncation, 30s timeout, HTTP error handling

### Storage
- `~/Library/Application Support/TermGrid/docs/docs-index.json` — doc metadata
- `~/Library/Application Support/TermGrid/docs/<uuid>.md` — fetched content
- Separate from `api-locker/` — clean security boundary
- Cascade delete: removing an API key deletes all associated docs

## Data Model
- `DocStatus` enum (.pending, .fetched, .error)
- `DocEntry` struct (id, keyEntryID, sourceURL, title, fetchedAt, status, errorMessage)
- `DocsIndex` struct (schemaVersion, entries)
- `isPremium: Bool` on `APILockerMetadata`

## Files Created
- `Sources/TermGrid/APILocker/DocsManager.swift`
- `Sources/TermGrid/APILocker/DocsTabView.swift`
- `Tests/TermGridTests/DocsManagerTests.swift`

## Files Modified
- `Sources/TermGrid/APILocker/APILockerMetadata.swift` (isPremium + custom decoder)
- `Sources/TermGrid/APILocker/APIKeyVault.swift` (isPremium accessor, onKeyRemoved callback)
- `Sources/TermGrid/APILocker/APILockerPanel.swift` (tabbed layout, DocsManager param)
- `Sources/TermGrid/Views/ContentView.swift` (hover tooltip, DocsManager passthrough)
- `Sources/TermGrid/TermGridApp.swift` (DocsManager init, cascade wiring)

## Testing
- 83 tests total (12 new for DocsManager, 2 new for APILockerMetadata)
- Covers: doc CRUD, URL validation, 10-doc limit, persistence round-trip, cascade delete, title extraction, backward-compatible decoding
