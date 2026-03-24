---
name: termgrid-parallel-subagents
description: Use when a TermGrid task is large enough for parallel agents or workers, including worktree creation, ownership boundaries, merge sequencing, and final integration validation.
---

# TermGrid Parallel Subagents

Use this skill when the task can be split into independent slices with low merge risk.

## Default Pattern
- Main checkout owns planning, integration, and final validation.
- Each worker gets one isolated git worktree.
- Each worker owns a disjoint subsystem or file set.

Create worktrees with:

```bash
./scripts/agent-worktree.sh create <task-name>
./scripts/agent-worktree.sh list
./scripts/agent-worktree.sh path <task-name>
```

## Good Splits
- UI view work vs model/persistence work
- terminal runtime work vs tests
- MLX/model lifecycle work vs autocomplete scoring
- notification transport work vs notification UI

## Bad Splits
- two workers editing the same state model
- overlapping migrations and UI wiring in the same files
- multiple workers changing shared command registries without ownership

## Worker Brief Requirements
- name the exact files or subsystem owned
- state the invariant the worker must preserve
- require targeted tests for that slice
- prohibit reverting unrelated edits

## Merge Order
1. land low-level model or runtime changes first
2. land UI wiring second
3. run targeted tests after each integration step
4. run full `swift test` in the main checkout

## Setup
If repo-local skills are not installed yet, run:

```bash
./scripts/install-repo-skills.sh all
```
