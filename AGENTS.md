# TermGrid V5 Agent Guide

This repository is a long-horizon macOS product, not a demo. Build for five-year durability: explicit state, narrow surfaces, tolerant persistence, predictable UI behavior, and tests that catch regressions before users do.

## First Read
- Read [docs/V5-HANDOVER.md](/Users/sam/Projects/TermGrid-V5/docs/V5-HANDOVER.md) before changing architecture or behavior.
- Read the relevant pack in [packs/](/Users/sam/Projects/TermGrid-V5/packs) before implementing a feature. Pack specs are the source of truth for scope.
- Check [CLAUDE.md](/Users/sam/Projects/TermGrid-V5/CLAUDE.md) for project rules and expected commands.

## Non-Negotiables
- Never mutate SwiftUI state during `body` evaluation or computed-property reads.
- Never put `NSHostingView` inside floating `NSPanel` or `NSWindow` surfaces that can appear during layout.
- Keep AppKit/SwiftUI boundaries explicit. Floating chrome, tooltips, and terminal-adjacent behavior should default to pure AppKit when stability matters.
- Treat persistence changes as schema work. Prefer tolerant decode, additive fields, and migration-safe defaults.
- Keep terminal behavior deterministic. Session startup, shutdown, env injection, scrollback restore, and detection hooks must survive restarts and partial failure.
- Validate with tests. Use targeted suites during iteration, then run `swift test` before closing the task.

## Code Map
- [Sources/TermGrid/Views](/Users/sam/Projects/TermGrid-V5/Sources/TermGrid/Views): SwiftUI surfaces and layout orchestration.
- [Sources/TermGrid/Terminal](/Users/sam/Projects/TermGrid-V5/Sources/TermGrid/Terminal): SwiftTerm integration, PTY/session lifecycle, output extraction.
- [Sources/TermGrid/Notifications](/Users/sam/Projects/TermGrid-V5/Sources/TermGrid/Notifications): agent hooks, structured events, reply routing.
- [Sources/TermGrid/Skills](/Users/sam/Projects/TermGrid-V5/Sources/TermGrid/Skills): skill storage, scanner, import/update flows.
- [Sources/TermGrid/Models](/Users/sam/Projects/TermGrid-V5/Sources/TermGrid/Models): persisted workspace data, UI state models, schema evolution pressure.
- [Sources/TermGridMLX](/Users/sam/Projects/TermGrid-V5/Sources/TermGridMLX): MLX-backed autocomplete enhancer and model lifecycle.
- [Tests/TermGridTests](/Users/sam/Projects/TermGrid-V5/Tests/TermGridTests): Swift Testing suites. Extend tests beside the subsystem you touch.

## Standard Execution Loop
1. Read the handover doc, then the specific pack or subsystem files you are changing.
2. Identify invariants first: state ownership, persistence impact, main-actor assumptions, and UI/event timing risks.
3. Implement in vertical slices that leave the app buildable.
4. Add or update targeted tests with the code change.
5. Run targeted tests while iterating, then `swift test` before handing work off.
6. If the change adjusts architecture or workflow expectations, update the relevant pack/spec or leave a short note in the repo.

## Repo Skills
Project-local skills live in [/.codex/skills](/Users/sam/Projects/TermGrid-V5/.codex/skills). Install them into `~/.codex/skills` and optionally `~/.claude/skills` with:

```bash
./scripts/install-repo-skills.sh all
```

High-value skills in this repo:
- `termgrid-pack-implementation`
- `termgrid-boss-orchestrator`
- `termgrid-worker-executor`
- `termgrid-swiftui-appkit-guardrails`
- `termgrid-terminal-runtime`
- `termgrid-persistence-evolution`
- `termgrid-testing-rigor`
- `termgrid-autocomplete-mlx`
- `termgrid-notifications-hooks`
- `termgrid-parallel-subagents`

## Parallel Agent Workflow
Use parallel agents only when the work cleanly decomposes into disjoint ownership. The default pattern in this repo is one integration branch plus one worktree per worker.

Create isolated worktrees with:

```bash
./scripts/agent-worktree.sh create <task-name>
./scripts/agent-worktree.sh list
./scripts/agent-status.sh
```

Rules:
- Give each worker a single owned slice: one subsystem or a clearly bounded file set.
- Do not assign overlapping write sets unless the follow-up merge is trivial.
- Keep integration work in the main checkout. Workers implement or verify bounded tasks in their own worktrees.
- Merge back only after the worker reports tests run for its slice.
- Run final integration validation in the main checkout with `swift test`.

### Boss Mode
- Use `Codex - Boss` in the main checkout as the single integration lane.
- `Codex - Boss` should poll the repo before assigning work, using `./scripts/agent-status.sh`.
- `Codex - Boss` can queue or reject tasks that overlap too heavily with active work.
- Worker panes should stay in their own worktrees and should not merge.
- See [docs/MULTI_AGENT_WORKFLOW.md](/Users/sam/Projects/TermGrid-V5/docs/MULTI_AGENT_WORKFLOW.md).

## Practical Defaults
- Prefer additive model changes over rewrites.
- Prefer explicit enums and typed state over stringly typed behavior.
- Prefer short-lived adapters over leaking third-party types across the app.
- Prefer targeted comments that explain invariants or timing assumptions.
- Prefer removing hidden coupling rather than documenting it.
