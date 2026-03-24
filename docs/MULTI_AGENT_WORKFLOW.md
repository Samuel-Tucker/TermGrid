# Multi-Agent Workflow

This is the simple workflow for running `Codex - Boss` plus 3-4 worker agents without turning the repo into a mess.

## Roles

### `Codex - Boss`
- stays in the main checkout
- reads your task request
- checks repo state and active worktrees
- decides whether the task can start now or should be queued
- creates the worktree and branch if the task is ready
- gives you the exact prompt to send to a worker pane
- teaches you why the split is safe or unsafe
- decides when to merge or when to stop agents

### Worker agents
- each works in exactly one worktree
- owns one pack or one bounded slice
- does not manage other agents
- reports changed files, tests run, and remaining risk

### You
- ask `Codex - Boss` for the next task
- rename panes so you can see who is doing what
- paste the worker prompt into the target pane
- bring results back to `Codex - Boss` for merge decisions

## The Simple Rule

Do not start a worker until `Codex - Boss` says one of these:
- `ready now`
- `safe to queue`
- `blocked by overlap`

That is the whole guardrail.

## Default Layout

- one pane named `Codex - Boss`
- one pane per worker, renamed to the task or pack
- one main checkout only for `Codex - Boss`
- one git worktree per worker

Use:
- [docs/BOSS_STARTER_PROMPT.md](/Users/sam/Projects/TermGrid-V5/docs/BOSS_STARTER_PROMPT.md) for the boss pane
- [docs/WORKER_STARTER_PROMPT.md](/Users/sam/Projects/TermGrid-V5/docs/WORKER_STARTER_PROMPT.md) for normal worker panes
- [docs/MULTI_AGENT_CHEATSHEET.md](/Users/sam/Projects/TermGrid-V5/docs/MULTI_AGENT_CHEATSHEET.md) for the fast session flow

## Worktree Model

Main checkout:
- planning
- polling repo state
- merging
- conflict resolution
- final test run

Worker checkout:
- implementation
- local file edits
- targeted tests
- local commit

Use:

```bash
./scripts/agent-worktree.sh create <task-name>
./scripts/agent-worktree.sh list
./scripts/agent-status.sh
```

## What You Say To `Codex - Boss`

Use simple requests. Examples:

- `Take pack 019 and split it safely into worker tasks.`
- `I want to add selection-to-note and slash commands. Can I run both now?`
- `I have 4 ideas. Decide what can run in parallel.`
- `Can I give this to Opus now, or is someone already in those files?`

## What `Codex - Boss` Should Do

Every time you ask for a task, `Codex - Boss` should:

1. Read the request.
2. Inspect current worktrees and dirty branches.
3. Check likely touched files or subsystems.
4. Decide:
   - start now
   - queue behind another task
   - merge first, then continue
   - stop a worker because overlap risk is too high
5. Explain the reason in plain language.
6. Give you the exact worker prompt if the task is approved.

## How To Keep Other Codex Panes From Becoming Boss

Do not rely on the model to "just know".

Instead:
- only one pane gets the Boss starter prompt
- every other Codex pane gets the Worker starter prompt
- worker prompts must explicitly say:
  - you are not the boss
  - you do not orchestrate
  - you do not merge
  - you stay inside owned files

This is enough in practice.

## Boss Decision Rules

### `ready now`
Use this when:
- the worker can own a separate subsystem
- or the overlap is tiny and easy to merge

### `queue it`
Use this when:
- another worker already owns the same subsystem
- the repo has an unstable integration point
- the task depends on an unfinished branch

### `merge first`
Use this when:
- two tasks are logically separate but share a low-level seam
- one branch needs to land before others can continue safely

### `stop agents`
Use this when:
- too many workers touched the same files
- the merge surface has become larger than the feature itself
- the repo is no longer green

## Beginner-Friendly Split Strategy

At first, split by layer, not by idea.

Good:
- worker 1: model/runtime
- worker 2: UI wiring
- worker 3: tests
- worker 4: docs/pack updates

Risky for beginners:
- worker 1 and 2 both changing `ContentView.swift`
- worker 1 and 2 both changing `CellView.swift`
- multiple workers all “implementing the same pack”

## Worker Prompt Template

`Codex - Boss` should give you something like this:

```text
Task: Implement Pack 032 compose submit parity.

Use the repo process in AGENTS.md.
Use these skills:
- termgrid-pack-implementation
- termgrid-terminal-runtime
- termgrid-testing-rigor

Worktree:
- .worktrees/pack-032-compose

Ownership:
- Sources/TermGrid/Terminal/TerminalSession.swift
- Sources/TermGrid/Views/ComposeBox.swift
- Tests/TermGridTests/TerminalSessionComposeTests.swift

Do not edit:
- Sources/TermGrid/Views/ContentView.swift
- Sources/TermGrid/Notifications/*
- unrelated packs

Required process:
1. Read docs/V5-HANDOVER.md
2. Read packs/032-compose-submit-parity.md
3. Implement only within owned files
4. Run targeted tests
5. Commit with a clear message
6. Report changed files, tests run, and risks
```

## Merge Process

Only `Codex - Boss` merges.

Default order:
1. runtime/model branches
2. UI branches
3. tests/docs branches

Commands from main checkout:

```bash
git checkout main
git merge --no-ff agent/<task-name>
swift test
```

If the worker branch is messy, `Codex - Boss` can cherry-pick the good commits instead.

## Polling Repo State

Use:

```bash
./scripts/agent-status.sh
```

This shows:
- active worktrees
- branch names
- whether each worktree is dirty
- changed files in each worktree

That is enough for `Codex - Boss` to make a rough overlap call.

## Teaching Mode

`Codex - Boss` should explain:
- why the task is safe or unsafe to parallelize
- what the likely conflict surface is
- what you should notice next time yourself

Short explanation format:
- `why safe`
- `why risky`
- `what to learn`

## Keep It Simple

Do not add:
- a task database
- auto-merging bots
- dependency graphs
- mandatory issue tickets
- queue daemons

You only need:
- one boss pane
- worker worktrees
- clear ownership
- one merge lane
- green tests
