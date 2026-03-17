# API Locker Enhancements — Docs, Premium, Hover Tooltip

**Date:** 2026-03-17
**Status:** Approved

## Overview

Three enhancements to the API Locker: (1) hover tooltip on the toolbar lock icon, (2) a premium-gated Docs tab for storing and fetching structured API documentation, and (3) a freemium model where docs are the premium unlock.

## 1. Toolbar Hover Tooltip

The lock icon button in the main toolbar gets a hover label.

- Label text: "API Locker"
- Style: 9pt rounded font, `Theme.cellBackground` pill background, subtle shadow
- Appears below the icon on hover, fades in
- No dock-style neighbor blur/magnification (it's isolated in the toolbar, not in a row of related icons)
- Implementation: `.overlay(alignment: .bottom)` with opacity animation on hover state
- **Remove** the existing `.help("API Locker")` modifier from the lock button in `ContentView.swift` — it would produce a duplicate native tooltip overlapping the custom one

## 2. Freemium Model

### Free Tier
- Full API Locker: store keys, PIN protection, Keychain encryption, env var injection into terminals
- Docs tab is **visible** in the panel but shows a premium gate (blurred preview + subscribe CTA)
- No doc storage, no URL entry, no fetching

### Premium Tier (£10/year)
- Everything in free
- Store up to 10 doc URLs per API key
- Auto-fetch and structure docs (via Jina Reader API, branded as TermGrid's own service)
- View structured docs inline in the panel
- Docs persist locally and are available as files for LLM consumption

### Implementation (V1 — placeholder)
- `isPremium: Bool` property on `APIKeyVault` (defaults to `false`)
- For development/testing: a toggle or hardcoded `true` to bypass the gate
- Subscribe button in the gate UI is a placeholder — opens a URL or shows "Coming soon"
- No payment backend, no license validation in V1
- The `isPremium` flag is stored in `api-locker/metadata.json` alongside existing PIN/salt fields
- **Backward compatibility:** `APILockerMetadata` currently uses auto-synthesized `Codable`. Adding `isPremium` requires a custom `init(from decoder:)` using `decodeIfPresent(_:forKey:) ?? false` to avoid breaking existing `metadata.json` files that lack this key. Without this, existing vaults would fail to decode and the user's vault would appear as `noVault` (data loss). Follow the tolerant-decode pattern used by `Cell` in `Workspace.swift`.
- **V1 security note:** `isPremium` is stored in plain JSON. This is a development convenience only. V2 must replace this with a signed license token or server-validated entitlement before any real payment flow ships.

## 3. Panel UI Changes

### Tabbed Layout
Add a `Picker` (segmented control style) at the top of the unlocked panel view:
- Two segments: **"Keys"** | **"Docs"**
- Keys tab: existing key list and add-key form (unchanged)
- Docs tab: new docs interface (or premium gate if free tier)
- Default selection: Keys

### Docs Tab — Premium Gate (free users)
- Blurred mockup preview of what the docs interface looks like with sample content
- Overlay: centered card with:
  - Lock icon
  - "API Documentation" heading
  - 2-3 bullet points of what premium unlocks
  - "Unlock with Premium — £10/year" button (placeholder action)
- Style matches existing Theme colors

### Docs Tab — Docs Interface (premium users)
- Docs are **grouped by API key** — each key with docs shows as a section header
- Under each key section: compact doc rows using progressive disclosure
- Empty state: `+ Add doc` button per key section
- Each added doc shows as a row: title + truncated URL + status indicator (green dot = fetched, spinner = fetching, red dot = error)
- `+ Add doc` button disappears when a key reaches 10 docs
- Count badge in tab header: "Docs (N)" where N is total doc count across all keys
- Clicking a doc row expands it inline to show the structured markdown content (read-only, scrollable, monospace, using existing Theme text colors)

### Doc Row Layout (320pt panel width)
```
┌──────────────────────────────────┐
│ ● OpenAI Chat Completions    ✕  │
│   api.openai.com/docs/...       │
└──────────────────────────────────┘
```
- Left: status dot (green/red/spinner)
- Center: title (12pt, `Theme.notesText`) + truncated URL below (10pt, `Theme.headerIcon`)
- Right: delete button (✕, with confirmation)
- Clicking the row toggles inline preview of the fetched markdown

### Add Doc Flow
1. User clicks `+ Add doc` under a key section
2. Inline text field appears: "Enter API docs URL..."
3. User pastes URL, hits Enter
4. **URL validation:** Must have `https://` or `http://` scheme. Reject anything else with inline error "Invalid URL — must be https"
5. Fetch starts immediately (inline spinner replaces status dot)
5. On success: row appears with title extracted from content, green dot
6. On failure: row appears with URL as title, red dot, error tooltip

## 4. Jina Reader Integration

### Branding
- Never mention "Jina" in the UI — this is "TermGrid Doc Fetch" or simply "fetching"
- The Jina API is an implementation detail, not a user-facing brand

### API Key Resolution (BYOK vs Premium)
- **BYOK path:** App looks up `JINA_API_KEY` from `vault.decryptedKeys`. If present, uses it directly for `r.jina.ai` calls.
- **Premium path (future):** App calls a TermGrid-hosted proxy that uses the premium Jina key server-side. Placeholder branch in code: `if isPremium { /* future proxy call */ } else { /* direct Jina with user's key */ }`
- **If neither available:** Fetch button disabled, message: "Add a JINA_API_KEY to your vault, or upgrade to Premium"

### API Call
- Endpoint: `GET https://r.jina.ai/{encoded_url}`
- Headers:
  - `Authorization: Bearer <jina_api_key>`
  - `Accept: text/markdown`
  - `X-Return-Format: markdown`
- Timeout: 30 seconds
- Max response size: 2MB (truncate with warning if exceeded)

### Error Handling
- Network failure → inline error on the doc row, retry button
- 401/403 → "Invalid or expired API key" error text
- 404 → "Page not found" error text
- Timeout → "Fetch timed out" with retry
- Response > 2MB → truncate, save what we have, show warning badge

### Title Extraction
- Parse first `# Heading` from the returned markdown
- If no heading found, use the URL's last path component
- User can edit the title after fetch

## 5. Storage Architecture

### Directory Layout
```
~/Library/Application Support/TermGrid/
├── workspace.json                    (existing)
├── api-locker/
│   └── metadata.json                 (existing — keys + isPremium flag)
└── docs/
    ├── docs-index.json               (new — doc entries metadata)
    └── <uuid>.md                     (new — fetched markdown files)
```

### Security Boundary
- `api-locker/` contains secret-adjacent data (PIN hash, key metadata). Unchanged.
- `docs/` contains public API documentation. No secrets. Clearly separated.
- Doc filenames use UUIDs, not key names or service names — no info leakage in filenames.

### Data Structures

```swift
struct DocEntry: Codable, Identifiable {
    let id: UUID
    let keyEntryID: UUID        // which API key this doc belongs to
    var sourceURL: String       // original URL entered by user
    var title: String           // extracted from markdown or user-edited
    var fetchedAt: Date         // when last fetched
    // fileName is computed: "\(id.uuidString).md" — not stored
    var status: DocStatus       // .fetched, .error, .pending
    var errorMessage: String?   // populated on fetch failure
}

enum DocStatus: String, Codable {
    case pending    // URL entered, not yet fetched
    case fetched    // successfully fetched and stored
    case error      // fetch failed
}
```

**Note on fetch-in-progress state:** Fetching status is tracked as a transient `@State` or `Set<UUID>` in `DocsManager` (e.g., `var fetchingIDs: Set<UUID>`), NOT as a `DocStatus` case. This prevents a `.fetching` status from being persisted to disk if the app crashes mid-fetch. On disk, an entry is always `.pending`, `.fetched`, or `.error`.

```swift
// In DocsManager:
var fetchingIDs: Set<UUID> = []  // transient, not persisted

struct DocsIndex: Codable {
    var schemaVersion: Int = 1
    var entries: [DocEntry]
}
```

### Persistence Pattern
- `DocsIndex` has static `save(_:to:)` and `load(from:)` methods matching `APILockerMetadata` pattern
- Atomic writes (`atomically: true`)
- Directory created on first save if it doesn't exist
- Doc content files are plain `.md` — readable by any text editor or LLM tool

## 6. DocsManager

`@MainActor @Observable` class managing doc lifecycle:

```swift
@MainActor
@Observable
final class DocsManager {
    private(set) var index: DocsIndex
    private let docsDirectory: URL

    func addDoc(url: String, forKey keyID: UUID) -> DocEntry?  // returns nil if limit (10) reached or invalid URL
    func fetchDoc(_ entry: DocEntry, apiKey: String) async throws
    func removeDoc(_ entry: DocEntry)
    func loadContent(for entry: DocEntry) -> String?
    func docsForKey(_ keyID: UUID) -> [DocEntry]
    var totalDocCount: Int
}
```

- `fetchDoc` is async — uses `URLSession` to call Jina, saves markdown to disk, updates index
- `loadContent` reads the `.md` file from disk on demand (not kept in memory)
- Index is saved after every mutation (add, remove, fetch completion)
- `removeDocsForKey(_ keyID: UUID)` — cascade-deletes all docs when a key is removed from the vault. `APIKeyVault.removeKey` must call this (or the caller must coordinate).
- 10-doc-per-key limit enforced in `addDoc` (returns nil if at limit)

**Note on existing `docsURL` field:** `APIKeyEntry` already has a `docsURL: String?` field. This is a display-only link (shown on key cards). The new `DocEntry` system is separate and richer — fetched, structured, viewable. No migration needed; they coexist. The existing `docsURL` remains as a quick-reference link on the key card.

## 7. Files

### New Files
| File | Purpose |
|------|---------|
| `Sources/TermGrid/APILocker/DocsManager.swift` | Doc lifecycle, Jina fetch, persistence |
| `Sources/TermGrid/APILocker/DocsTabView.swift` | Docs tab UI: premium gate, doc list, add flow, inline preview |
| `Tests/TermGridTests/DocsManagerTests.swift` | Tests for doc CRUD, index persistence, title extraction |

### Modified Files
| File | Changes |
|------|---------|
| `APILockerPanel.swift` | Add `Picker` for Keys/Docs tabs, pass DocsManager to DocsTabView |
| `APIKeyVault.swift` | Add `isPremium: Bool` to vault state, persist in metadata |
| `APILockerMetadata.swift` | Add `isPremium` field with tolerant decoding (defaults `false`) |
| `ContentView.swift` | Add hover tooltip to lock button, initialize DocsManager |
| `TermGridApp.swift` | Create `@State private var docsManager = DocsManager()` alongside vault, pass through view hierarchy |
| `APIKeyVault.swift` | `removeKey` must call `DocsManager.removeDocsForKey` to cascade-delete orphaned docs |

**DocsManager ownership:** `DocsManager` is `@State` in `TermGridApp`, receives its docs directory URL at init (defaults to `~/Library/Application Support/TermGrid/docs/`). Its `fetchDoc` method takes an `apiKey: String` parameter — the caller resolves the key from the vault. This avoids DocsManager depending on APIKeyVault directly.

## 8. Out of Scope (V1)
- Payment integration / license validation
- Premium proxy server for Jina calls
- Doc re-fetching / refresh on demand (can add later)
- Doc search across all stored docs
- Syntax highlighting in doc preview
- Export/import of docs bundle
- Sharing docs between machines (manual file copy works via Application Support)
