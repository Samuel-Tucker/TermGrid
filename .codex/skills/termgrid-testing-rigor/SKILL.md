---
name: termgrid-testing-rigor
description: Use when adding or refactoring Swift Testing coverage in TermGrid, choosing targeted suites, writing temp-directory tests, and closing tasks with robust validation.
---

# TermGrid Testing Rigor

Use this skill whenever a task changes behavior, not just when a test is already failing.

## Standard Pattern
1. Find the nearest existing suite in `Tests/TermGridTests`.
2. Extend that suite unless a new suite is clearer.
3. Use Swift Testing (`@Suite`, `@Test`, `#expect`), not XCTest.
4. Keep tests deterministic with temp directories and injected paths.
5. Run focused suites during iteration, then `swift test`.

## Good Test Targets
- persistence round trips
- tolerant decode and migration paths
- command registration and filtering
- terminal/session lifecycle decisions
- extractor/parser logic
- state-model behavior without UI rendering

## Avoid
- tests that rely on real home-directory state
- wide integration tests when a model-level test would catch the issue
- assertions on unstable timestamps or unordered output without normalization

## Handy Suites
- `PersistenceManagerTests`
- `WorkspaceStoreTests`
- `SkillScannerTests`
- `SkillsManagerTests`
- `TerminalSessionManagerTests`
- `SessionRestoreTests`
- `CommandRegistryTests`

## Close-Out
- If a change is hard to test directly, explain the gap and test the next most stable seam.
- Full `swift test` is the final gate.
