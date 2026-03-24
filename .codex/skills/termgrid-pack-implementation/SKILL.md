---
name: termgrid-pack-implementation
description: Use when implementing any numbered pack or translating TermGrid handover/spec documents into code, tests, and staged validation.
---

# TermGrid Pack Implementation

Use this skill for feature work driven by `packs/` or `docs/V5-HANDOVER.md`.

## Workflow
1. Read `docs/V5-HANDOVER.md`, `CLAUDE.md`, and the target pack before editing code.
2. Identify touched subsystems: `Views`, `Terminal`, `Notifications`, `Models`, `Skills`, or `TermGridMLX`.
3. List invariants before coding:
   - persistence compatibility
   - `@MainActor` and Observation ownership
   - SwiftUI/AppKit boundary risks
   - performance or latency budgets
4. Implement in thin slices that compile after each step.
5. Add targeted tests in `Tests/TermGridTests`.
6. Run focused tests first, then `swift test`.

## TermGrid-Specific Rules
- Pack scope is binding. Do not silently widen V1 scope.
- If a pack says "do NOT", treat that as an explicit non-goal.
- Preserve existing V4.1 behavior unless the pack intentionally changes it.
- If a pack implies schema changes, use tolerant decode and safe defaults.

## Useful Reads
- `docs/V5-HANDOVER.md`
- `packs/<number>-*.md`
- `Sources/TermGrid/...` for the touched subsystem
- matching test suites in `Tests/TermGridTests`

## Validation Pattern
- Start with one or two targeted suites that cover the changed module.
- Run full `swift test` before closing the task.
- If the task changes user-facing workflows, re-read the pack after implementation and check for drift.
