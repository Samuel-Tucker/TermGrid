# Pack 018: External Secrets Integration

**Type:** Feature Spec
**Priority:** Low
**Competitors:** Warp

## Problem

Power users already have secrets in 1Password or `.env` files and don't want to duplicate them manually.

## Solution

Import-only flow (one-time copy into TermGrid vault). Not live linkage — that's a different product.

### V1 scope (narrowed per Codex feedback):
- **.env file import** — realistic, well-defined format
- **1Password CLI import** — `op` handles its own auth (Touch ID)
- **NO macOS Keychain browsing** — TermGrid already stores in Keychain via `APIKeyVault`. Browsing the whole Keychain is inconsistent UX and produces unreliable results. Removed.

### .env parsing (properly specified):
- Format: `KEY=value`, one per line
- Handle: `export KEY=value`, `KEY="quoted value"`, `KEY='single quoted'`
- Skip: comments (`#`), blank lines
- Error on: duplicate keys (show inline warning with skip/replace options)
- Ignore: variable expansion (`$OTHER_VAR`) — import literal values only

### 1Password CLI flow:
- Check `which op` — if not installed, show "Install 1Password CLI" link
- Run `op item list --categories=api-credential,password --format=json` (filter by category, not all items)
- Show list with checkboxes for selection
- For each selected: `op item get {id} --fields=credential --format=json` to get the actual secret value
- Requires vault selection if user has multiple vaults

### Collision handling (Codex flagged this):
- Before import: check for existing keys with same env var name
- Options: **Skip**, **Replace**, **Rename** (append `-2`)
- Show collision summary before executing import

### Post-import behavior:
- Clear message: "Keys imported. New terminals will see these variables. Restart existing terminals to pick up changes."
- Offer "Restart all terminals" button

### UI fit:
- **"Import Keys" button** at the bottom of the Keys tab in API Locker panel (next to "Add API Key" toggle area)
- **Opens a sheet** (not inline — the 320px locker panel is too narrow for a multi-step import flow)
- Sheet has tabs: ".env File" | "1Password"

### Implementation:
- `SecretsImporter` protocol: `func listAvailable() async throws -> [ImportableKey]`, `func fetchValue(for:) async throws -> String`
- `DotEnvImporter`, `OnePasswordImporter` conformances
- `ImportSheet` SwiftUI view with file picker / item list / collision resolution
- Values go through existing `APIKeyVault.addKey()` flow
- Handle: vault auto-lock timer may fire during long import — extend lock timeout during import flow

### UI impact: 1 button in existing API Locker panel + modal sheet. No global UI change.
