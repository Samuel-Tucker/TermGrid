# Pack 026: Ghost Autocomplete (Local Learning)

## Context

Users type the same commands and prompt patterns repeatedly. The phantom compose box should learn from what users type and offer VS Code-style ghost text predictions — dimmed text that appears ahead of the cursor, accepted with Tab.

**Inspiration:** Fish shell's instant history suggestions, VS Code's inline completions, Warp AI's command predictions.

**Key constraint:** Everything runs locally. No cloud. No API calls. The system ships with zero dependencies in Phase 1 (pure Swift n-gram), with an optional MLX LLM upgrade in Phase 2.

**Public distribution:** Any Mac user clones the repo, builds with `swift build`, and the learning system bootstraps automatically from their shell history.

**Scope:** Ghost text is phantom-compose-only. The classic `ComposeBox` code path is excluded from this pack.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                     Ghost Autocomplete System                 │
│                                                               │
│  ┌─────────┐    ┌──────────┐    ┌──────────┐    ┌─────────┐ │
│  │ Corpus   │───▶│ Trigram  │───▶│ Scorer   │───▶│ Ghost   │ │
│  │ (GRDB/  │    │ Engine   │    │ (Decay)  │    │ Text UI │ │
│  │  SQLite) │    │          │    │          │    │(overlay)│ │
│  └─────────┘    └──────────┘    └──────────┘    └─────────┘ │
│       ▲              ▲                               │       │
│       │              │                               ▼       │
│  ┌─────────┐    ┌──────────┐                   ┌─────────┐  │
│  │ History  │    │ In-Memory│                   │ Feedback│  │
│  │ Import   │    │ Trie     │                   │ Loop    │  │
│  └─────────┘    │(from DB) │                   └─────────┘  │
│                  └──────────┘                                 │
│  Phase 2 (opt-in, separate SPM target):                      │
│  ┌──────────────────────────────────┐                        │
│  │ MLX LLM (Qwen2.5-0.5B Q4)      │                        │
│  │ Async enhancer when n-gram      │                        │
│  │ confidence < 0.6                │                        │
│  └──────────────────────────────────┘                        │
└──────────────────────────────────────────────────────────────┘
```

## Red-Team Fixes Applied

This spec incorporates fixes from adversarial review (Opus red-team, 2026-03-19):

- **C1:** Tab key handling added to phantom mode key routing
- **C2:** SQLite library specified (GRDB.swift) + added to Package.swift
- **C3:** Ghost text rendering via separate overlay NSView, not attributed string manipulation
- **C4:** Option+Tab replaced with Right Arrow at end-of-text for word-accept
- **C5:** `cursorLineText` exposed from ComposeNSTextView for multi-line prediction
- **W2:** Decay math corrected (half-life 11 days for ~15% at 30 days)
- **W3:** Base corpus confidence set to 0.7 (above 0.6 threshold) to fix cold-start chicken-and-egg
- **W5:** Agent detection corpus assignment noted as best-effort
- **W6:** Ghost text suppressed when compose history is active
- **W8:** In-memory trie loaded at launch; SQLite for persistence only
- **W9:** 50ms debounce added for n-gram predictions
- **W10:** Tokenizer simplified to whitespace-split with quote awareness
- **O1:** Shell history import sanitizes common secret patterns
- **O5:** EMA alpha reduced to 0.15 for more stable confidence
- **O6:** Compose history migrated to autocomplete DB (single source of truth)

## Phase 1: N-gram Engine (Pure Swift + GRDB)

### Dependency

Add to `Package.swift`:
```swift
.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
```

GRDB.swift provides type-safe SQLite with Codable record support. It links against macOS system `libsqlite3` — no embedded database binary needed.

### Data Model

**SQLite database:** `~/Library/Application Support/TermGrid/autocomplete.db`

```sql
-- Raw command history (replaces ComposeHistoryEntry in workspace.json)
-- Also serves as the data source for Ctrl+R compose history popup
CREATE TABLE corpus (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    domain TEXT NOT NULL DEFAULT 'shell',  -- 'shell' or 'prompt'
    timestamp REAL NOT NULL,               -- Unix epoch
    accepted_from_suggestion INTEGER DEFAULT 0,  -- 1 if Tab-accepted
    working_directory TEXT DEFAULT ''       -- for per-project weighting (O3)
);

-- Trigram counts (precomputed from corpus)
CREATE TABLE trigrams (
    w1 TEXT NOT NULL,
    w2 TEXT NOT NULL,
    w3 TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 1,
    last_used REAL NOT NULL,
    confidence REAL NOT NULL DEFAULT 0.5,
    PRIMARY KEY (w1, w2, w3)
);

-- Prefix index for trie-style lookups
CREATE TABLE prefixes (
    prefix TEXT NOT NULL,
    completion TEXT NOT NULL,
    frequency INTEGER NOT NULL DEFAULT 1,
    last_used REAL NOT NULL,
    domain TEXT NOT NULL DEFAULT 'shell',
    PRIMARY KEY (prefix, completion, domain)
);

CREATE INDEX idx_prefix ON prefixes(prefix, domain);
CREATE INDEX idx_trigram ON trigrams(w1, w2);
CREATE INDEX idx_corpus_timestamp ON corpus(timestamp DESC);
```

### In-Memory Trie (loaded at launch)

SQLite is for persistence only. At app launch, load prefixes and trigrams into in-memory Swift data structures for sub-millisecond lookups:

```swift
final class TrieNode {
    var children: [Character: TrieNode] = [:]
    var completions: [(text: String, score: Double)] = []  // top-10, pre-sorted
}

// Loaded from SQLite on launch, synced back on writes (debounced)
final class InMemoryAutocompleteModel {
    var trie: TrieNode = TrieNode()
    var trigrams: [TrigramKey: [String: TrigramEntry]] = [:]

    func rebuild(from db: DatabaseQueue) { ... }
}
```

This guarantees <1ms prefix lookups regardless of corpus size.

### Tokenizer (Simplified per W10)

Whitespace-split with quote awareness. No semantic token types — the trigram model doesn't need them and complex tokenization creates more bugs than value.

```swift
func tokenize(_ input: String) -> [String] {
    // Split on whitespace, but keep quoted strings together
    // "git commit -m \"hello world\"" → ["git", "commit", "-m", "\"hello world\""]
    var tokens: [String] = []
    var current = ""
    var inQuote: Character? = nil

    for char in input {
        if let q = inQuote {
            current.append(char)
            if char == q { inQuote = nil }
        } else if char == "\"" || char == "'" {
            inQuote = char
            current.append(char)
        } else if char.isWhitespace {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else {
            current.append(char)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}
```

### Trigram Engine

**Order:** Trigram (n=3). Captures patterns like `git commit -m`, `docker run -it`.

```swift
struct TrigramKey: Hashable {
    let w1: String  // two tokens back
    let w2: String  // one token back
}

struct TrigramEntry {
    var count: UInt32
    var lastUsed: Date
    var confidence: Double
}

// Given previous two tokens, predict next token
func predict(w1: String, w2: String) -> [(token: String, score: Double)]
```

**Lookup flow:**
1. User types `git comm`
2. In-memory trie prefix lookup for `comm` → candidates: `[commit, command, comment]`
3. For each candidate, score with trigram: `P(candidate | <START>, git)`
4. Apply exponential decay weighting
5. Return highest-scoring candidate as ghost text

**Debounce:** 50ms after last keystroke before running prediction (prevents redundant computation during rapid typing).

### Scoring: Exponential Decay

```swift
func score(frequency: Double, lastUsed: Date, now: Date) -> Double {
    let days = now.timeIntervalSince(lastUsed) / 86400
    let halfLife = 11.0  // 11-day half-life
    let lambda = pow(0.5, 1.0 / halfLife)
    return frequency * pow(lambda, days)
}
```

Corrected decay values:
- Commands from yesterday: ~94% weight
- Commands from last week: ~64% weight
- Commands from 30 days ago: ~15% weight
- Commands from 60 days ago: ~2% weight (effectively pruned)

### Confidence Gating

Only show ghost text when prediction confidence > 0.6.

```swift
func shouldShowGhost(_ prediction: Prediction) -> Bool {
    prediction.confidence >= 0.6
}
```

**Cold-start fix:** Base corpus entries are inserted with `confidence = 0.7` (above threshold) so they appear immediately. User-generated entries start at 0.5 and must be accepted once to cross 0.6.

### Feedback Loop

```
Tab pressed (accept):
  → frequency += 1.0
  → lastUsed = now
  → confidence = 0.15 * 1.0 + 0.85 * old_confidence  (EMA alpha=0.15)
  → save accepted text to corpus with accepted_from_suggestion=1

User types over suggestion (reject):
  → confidence = 0.15 * 0.0 + 0.85 * old_confidence  (= 0.85 * old)
  → what they actually typed gets boosted
  → temporary suppression for this prefix→completion pair (session only)
```

Alpha=0.15 (reduced from 0.3) makes confidence more stable:
- From default 0.5: 1 accept → 0.575, 2 accepts → 0.639 (crosses threshold)
- From 0.7: 1 reject → 0.595 (still just below threshold — graceful degradation)
- Recovery from rejection: 2 accepts → back above 0.6

### Mutual Exclusion with Compose History

Ghost text is suppressed when `composeHistoryActive == true`. These are mutually exclusive UI states — showing both would make Tab ambiguous.

### Corpus Separation

Two models, one interface:

| Domain | Trained on | Context signal |
|--------|-----------|----------------|
| `shell` | `~/.zsh_history` + sent commands | Default when typing in terminal |
| `prompt` | Agent prompts the user has sent | When agent is detected (Claude, Codex, etc.) |

Detection: if `session.detectedAgent != nil`, use prompt model. Otherwise shell model.

**Note:** Agent detection is best-effort — the first few commands in a new agent session may use the shell model before the agent banner is detected.

### Cold-Start Bootstrap

**First launch flow:**
1. Check for `~/.zsh_history` → show opt-in dialog: "Import shell history for smarter suggestions?"
   - **Security:** Sanitize imports by stripping values after `=` in patterns matching `KEY=value`, `export VAR=`, and common secret prefixes (`sk-`, `ghp_`, `Bearer `)
2. If accepted, parse zsh format (`: timestamp:duration;command`) and index in background
3. Load base corpus from app bundle: `Resources/base-corpus.json`
4. Ghost text begins appearing immediately for base corpus entries (confidence=0.7)

**Base corpus format (`base-corpus.json`):**
```json
{
  "version": 1,
  "entries": [
    { "command": "git status", "domain": "shell" },
    { "command": "git commit -m", "domain": "shell" },
    { "command": "docker run -it --rm", "domain": "shell" },
    ...
  ]
}
```

~500 entries covering: git, docker, npm, kubectl, brew, swift, python, curl, ssh, find, grep.

**For new public users:**
- App works immediately with base corpus
- Gets smarter within first hour of use
- Import button always available in Command Palette

## Phase 2: MLX Local LLM (Opt-in)

### Separate SPM Target

MLX is added as a **separate Swift package target** (`TermGridMLX`) to avoid bloating builds for users who don't opt in:

```swift
// In Package.swift
.target(name: "TermGridMLX", dependencies: ["mlx-swift", ...]),
.target(name: "TermGrid", dependencies: [
    "SwiftTerm", "MarkdownUI", "GRDB",
    .target(name: "TermGridMLX", condition: .when(platforms: [.macOS]))
])
```

### Model Selection

**Qwen2.5-0.5B-Instruct (Q4 quantized)**
- ~300MB download
- ~50 tokens/sec on M1, ~100+ on M3/M4
- Instruction-tuned: understands "complete this command"

### Integration Pattern

MLX runs as an **async enhancer**, not a replacement:

```
User types →
  ├─ N-gram engine responds in <20ms → show ghost text immediately
  │
  └─ If n-gram confidence < 0.6:
       ├─ Dispatch MLX query (debounced 150ms after last keystroke)
       ├─ MLX responds in 50-200ms
       └─ If MLX result is better, replace ghost text with smooth crossfade
```

### Model Management

```
Settings Panel / Command Palette:
  ├─ "AI Autocomplete" section
  │   ├─ Toggle: "Enable AI-powered suggestions"
  │   ├─ Status: "Model: Qwen2.5-0.5B (300MB) — Downloaded ✓"
  │   ├─ Button: "Download Model" / "Remove Model"
  │   └─ Progress bar during download
  │
  Storage: ~/Library/Application Support/TermGrid/models/
```

### Prompt Format

```
<|im_start|>system
Complete the user's partial terminal command or prompt.
Respond with ONLY the completion text after the cursor position.
Do not repeat what the user has already typed.
<|im_end|>
<|im_start|>user
Context: macOS terminal, working directory /Users/sam/Projects/TermGrid-V4
Partial input: docker run -it --rm
<|im_end|>
<|im_start|>assistant
```

### Context Window (Phase 2+)

Include last 50 lines of terminal output as context. This enables "magic" predictions:
- After `error in main.swift:42` → suggest `vim Sources/TermGrid/main.swift +42`
- After `npm test` failure → suggest the failing test command

## Phase 3: Personal Fine-tuning (Future)

- LoRA fine-tune on user's accepted completions
- Runs overnight or on-demand
- Model learns user's specific project names, branch naming conventions, argument patterns
- Fine-tuned adapter stored alongside base model (~10MB)

## Ghost Text UI Spec

### Visual Design

```
┌─────────────────────────────────────────────┐
│ ⇧Enter send  Esc dismiss  ^R history       │
│ git comm│it -m "fix: update tests"          │
│         ↑                                    │
│     cursor    ← ghost text in 30% opacity → │
└─────────────────────────────────────────────┘
```

### Rendering Approach (fixes C3, O4)

Ghost text is rendered via a **separate transparent NSView overlay** positioned at the cursor location inside `ComposeNSTextView`. This avoids:
- Contaminating `textStorage` (which would break the `text` binding sync in `updateNSView`)
- Fighting `isRichText = false` mode
- Polluting the undo stack

```swift
// Inside ComposeNSTextView
private lazy var ghostOverlay: NSTextField = {
    let field = NSTextField(labelWithString: "")
    field.font = self.font
    field.textColor = Theme.composeText.withAlphaComponent(0.30)
    field.backgroundColor = .clear
    field.isBezeled = false
    field.isEditable = false
    addSubview(field)
    return field
}()

func showGhostText(_ text: String) {
    ghostOverlay.stringValue = text
    // Position at cursor using layoutManager glyph rect
    let glyphIndex = layoutManager!.glyphIndexForCharacter(at: selectedRange().location)
    let glyphRect = layoutManager!.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1),
                                                 in: textContainer!)
    ghostOverlay.frame.origin = NSPoint(x: glyphRect.maxX, y: glyphRect.origin.y)
    ghostOverlay.sizeToFit()
    ghostOverlay.isHidden = false
}

func hideGhostText() {
    ghostOverlay.isHidden = true
}
```

### Cursor Line Extraction (fixes C5)

For multi-line compose, the prediction engine needs the current line:

```swift
// In ComposeNSTextView
var cursorLineText: String {
    let text = self.string
    let cursorPos = selectedRange().location
    let nsString = text as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: cursorPos, length: 0))
    return nsString.substring(with: lineRange).trimmingCharacters(in: .newlines)
}
```

Exposed to SwiftUI layer via the coordinator's `textDidChange` callback.

### Key Bindings (fixes C1, C4)

| Key | Action |
|-----|--------|
| Tab (keyCode 48) | Accept full ghost suggestion (must be added to `handlePhantomKeyDown/KeyEquivalent`) |
| Right Arrow (at end of typed text, ghost visible) | Accept next word only |
| Any other key | Dismiss ghost, continue typing normally |
| Escape | Dismiss ghost (existing behavior) |

**Tab handling in ComposeNSTextView** (critical — without this, Tab inserts `\t`):

```swift
// In handlePhantomKeyDown:
// Tab = accept ghost text (if visible)
if event.keyCode == 48 {  // Tab
    if !ghostOverlay.isHidden {
        onGhostAccept?()
    }
    return  // never insert \t in phantom mode
}
```

### Latency Targets

| Source | Target | Acceptable |
|--------|--------|------------|
| In-memory Trie | <1ms | <5ms |
| Trigram scoring | <5ms | <15ms |
| Total n-gram | <10ms | <20ms |
| Debounce delay | 50ms | — |
| MLX LLM (Phase 2) | <200ms | <500ms |
| Ghost render | <1 frame (16ms) | <2 frames |

## Implementation Steps

### Phase 1A: Data Layer
1. Add GRDB.swift to `Package.swift`
2. `Autocomplete/AutocompleteDB.swift` — GRDB wrapper (schema, migrations, CRUD)
3. `Autocomplete/Tokenizer.swift` — Whitespace-split with quote awareness
4. `Autocomplete/TrigramEngine.swift` — Build/query trigram model
5. `Autocomplete/InMemoryTrie.swift` — In-memory prefix index loaded from DB
6. `Autocomplete/HistoryImporter.swift` — Parse ~/.zsh_history with secret sanitization

### Phase 1B: Prediction Engine
7. `Autocomplete/CompletionEngine.swift` — Unified interface with 50ms debounce
8. `Autocomplete/Scorer.swift` — Exponential decay (half-life 11 days) + confidence gating
9. `Autocomplete/FeedbackRecorder.swift` — Accept/reject signals, EMA alpha=0.15

### Phase 1C: Ghost Text UI
10. `ComposeNSTextView` — Add ghost overlay NSTextField, Tab handling, `cursorLineText`
11. `PhantomComposeOverlay` — Wire ghost text lifecycle (show/hide/accept)
12. Hint bar — Show "Tab accept" when ghost is visible, hide when not

### Phase 1D: Bootstrap & Settings
13. `Resources/base-corpus.json` — 500 common shell patterns (confidence=0.7)
14. First-launch import dialog with sanitization
15. Command palette: "Import Shell History", "Clear Autocomplete Data", "Toggle Autocomplete"

### Phase 1E: Migrate Compose History
16. Migrate `ComposeHistoryEntry` from workspace.json to autocomplete.db corpus table
17. Update `ComposeHistoryPopup` to query SQLite instead of workspace array
18. Remove `composeHistory` from `Workspace` struct (backward-compatible decode)

### Phase 2: MLX Integration (separate SPM target)
19. Create `TermGridMLX` target with mlx-swift dependency
20. `MLX/MLXCompletionProvider.swift` — Async LLM query with 150ms debounce
21. `MLX/ModelManager.swift` — Download/manage models, progress UI
22. Hybrid routing: n-gram first, MLX enhances when confidence < 0.6

### Phase 3: Personal Fine-tuning
23. LoRA training pipeline on accepted completions
24. Scheduled fine-tuning (overnight or manual trigger)
25. Adapter storage and hot-swap

## Critical Files

| File | Purpose | Phase |
|------|---------|-------|
| `Package.swift` | Add GRDB.swift dependency | 1A |
| `Autocomplete/AutocompleteDB.swift` | SQLite schema + CRUD via GRDB | 1A |
| `Autocomplete/Tokenizer.swift` | Whitespace-split tokenizer | 1A |
| `Autocomplete/TrigramEngine.swift` | N-gram prediction model | 1A |
| `Autocomplete/InMemoryTrie.swift` | Fast prefix lookup (loaded from DB) | 1A |
| `Autocomplete/CompletionEngine.swift` | Unified prediction with debounce | 1B |
| `Autocomplete/HistoryImporter.swift` | Shell history bootstrap + sanitization | 1D |
| `Resources/base-corpus.json` | 500 common commands, confidence=0.7 | 1D |
| `Views/ComposeBox.swift` | Ghost overlay, Tab accept, cursorLineText | 1C |
| `Views/CellView.swift` | Wire ghost text into phantom compose | 1C |
| `CommandPalette/CommandRegistry.swift` | Import/clear/toggle commands | 1D |
| `TermGridMLX/MLXCompletionProvider.swift` | Local LLM inference | 2 |
| `TermGridMLX/ModelManager.swift` | Download/manage MLX models | 2 |

## Edge Cases

- **Empty compose box:** Don't show ghost text on first character (wait for 2+ chars or after a space)
- **Multi-line input:** Predict based on current cursor line only (via `cursorLineText`)
- **Paste:** Don't trigger ghost text on paste operations (detect via `NSTextView.paste(_:)` override)
- **Compose history active:** Suppress ghost text when `composeHistoryActive == true`
- **Agent shutter active:** Still allow ghost text — user may be queueing commands
- **Multiple cells:** Each cell shares the same global autocomplete DB, with `working_directory` for future per-project weighting
- **Performance:** In-memory trie guarantees <1ms lookups. SQLite writes are debounced/batched.
- **Corpus growth:** Prune entries with confidence < 0.1 and age > 90 days on app launch
- **Shell history secrets:** Sanitize `KEY=value`, `export VAR=secret`, `Bearer`, `sk-`, `ghp_` patterns on import

## Verification

### Phase 1A (Data Layer)
- Unit tests for tokenizer: pipes, quotes, flags, paths, empty input, unicode
- Unit tests for trigram build + query + decay scoring
- Unit tests for GRDB schema creation and CRUD
- Unit tests for trie build + prefix lookup
- Import test with sample .zsh_history fixture (including secret sanitization)

### Phase 1C (Ghost Text)
- Manual: type `git co` → see `mmit` ghost text (dimmed, after cursor)
- Manual: press Tab → text accepted, ghost disappears, feedback recorded
- Manual: type `docker r` → see `un -it` ghost text
- Manual: type over suggestion → ghost dismissed, rejection recorded
- Manual: cold start with base corpus only → common commands suggest immediately
- Manual: Ctrl+R (history) → ghost text hidden while popup is open
- Manual: Right Arrow at end of text → accepts one word of ghost text

### Phase 2
- Manual: enable AI mode → model downloads with progress bar
- Manual: type partial command → n-gram shows first, LLM refines after 150ms pause
- Manual: disable AI mode → model unloaded, n-gram only
