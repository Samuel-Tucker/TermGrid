---
name: termgrid-persistence-evolution
description: Use for TermGrid persistence changes, schema evolution, tolerant decoding, app-support storage, repo-local notes, and migration-safe model updates.
---

# TermGrid Persistence Evolution

Use this skill when changing anything stored on disk.

## Storage Surfaces
- `workspaces.json`
- `skills.json`
- docs indices and fetched docs
- autocomplete database and corpus state
- repo-local `.termgrid/notes`

## Rules
- Default to additive changes.
- Prefer tolerant decoding and explicit fallback values.
- Do not require users to delete state to recover from schema changes.
- Keep storage paths centralized and testable.
- If a model is partly ephemeral, do not accidentally persist it.

## Migration Checklist
1. Identify the storage file or database touched.
2. Check current decode/init behavior for missing fields.
3. Add compatibility logic before writing new data.
4. Add tests for old-shape and new-shape payloads when practical.
5. Verify temp-directory tests, not the real app-support directory.

## Files To Inspect
- `Sources/TermGrid/Models/*.swift`
- `Sources/TermGrid/Skills/SkillsManager.swift`
- `Sources/TermGrid/APILocker/DocsManager.swift`
- persistence-related tests in `Tests/TermGridTests`

## Validation
- Use temp directories.
- Add regression tests for decode/load/save round trips.
- Run full `swift test` after changing persisted models.
