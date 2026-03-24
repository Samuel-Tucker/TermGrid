---
name: termgrid-autocomplete-mlx
description: Use for TermGrid ghost autocomplete, trie and GRDB learning loops, scoring changes, confidence behavior, MLX fallback, and latency-sensitive suggestion work.
---

# TermGrid Autocomplete MLX

Use this skill for `Autocomplete/` and `TermGridMLX/`.

## Design Intent
- n-gram and trie paths stay fast and local
- MLX is an async enhancer, not the primary path
- user trust depends on low-latency, non-annoying suggestions

## Guardrails
- Preserve immediate local predictions even when MLX is enabled.
- Be careful with confidence penalties and learning triggers; avoid feedback spirals.
- Keep model lifecycle separate from suggestion rendering.
- Avoid main-thread blocking during model checks, download, or load.
- Treat stale-generation protection as mandatory, not optional.

## When Editing
1. Inspect the scoring and acceptance path first.
2. Check whether a change affects learning, rendering, or MLX generation timing.
3. Keep debounce, generation ID, and stale-result handling coherent.
4. Add tests for the exact regression class, especially confidence decay or stale replacement.

## Files To Inspect
- `Sources/TermGrid/Autocomplete/*`
- `Sources/TermGridMLX/MLXCompletionProvider.swift`
- `Sources/TermGridMLX/ModelManager.swift`
- autocomplete-related suites in `Tests/TermGridTests`

## Validation
- Run focused autocomplete and MLX-adjacent suites first.
- Finish with full `swift test`.
