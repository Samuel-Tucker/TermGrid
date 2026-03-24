# Multi-Agent Cheatsheet

Use this when you want to start a session quickly without thinking about process design.

## 1. Session Boot Sequence

### Step 1: Open panes
- one pane named `Codex - Boss`
- up to 3 worker panes
- rename worker panes after the task once assigned

### Step 2: In `Codex - Boss`
Paste:
- [docs/BOSS_STARTER_PROMPT.md](/Users/sam/Projects/TermGrid-V5/docs/BOSS_STARTER_PROMPT.md)

Then run:

```bash
./scripts/agent-status.sh
./scripts/agent-worktree.sh list
```

### Step 3: In each worker pane
Paste:
- [docs/WORKER_STARTER_PROMPT.md](/Users/sam/Projects/TermGrid-V5/docs/WORKER_STARTER_PROMPT.md)

Do not give the worker a task yet.

### Step 4: Ask Boss what can start
Use one of the prompts below.

## 2. Ask Boss For A Task

### Fast version

```text
I want to work on Pack 019. Check current repo/worktree state, decide if it is safe to start now, and if so create the worktree and give me the exact worker prompt.
```

### Multiple ideas version

```text
I have these ideas:
1. Pack 019 notification improvements
2. compose slash commands
3. file explorer polish
4. notes workflow improvement

Check repo state, decide what can run in parallel safely, queue anything risky, and give me one worker prompt at a time.
```

### Overlap check version

```text
Can I start this task now, or should it queue behind an existing worker? Explain why in beginner-friendly terms.
```

## 3. What Boss Should Send Back

You want Boss to reply in this structure:

```text
Decision: ready now / queue it / merge first / stop agents

Why:
- ...

What this teaches you:
- ...

Run:
- ./scripts/agent-worktree.sh create <task-name>

Send this to your worker:
<worker prompt>
```

## 4. Worker Task Prompt Template

Boss should fill this in and send it back to you:

```text
Task: <clear task name>

Use the repo process in AGENTS.md.

Use these skills:
- <skill 1>
- <skill 2>
- <skill 3>

Worktree:
- .worktrees/<task-name>

Ownership:
- <owned file or subsystem 1>
- <owned file or subsystem 2>

Do not edit:
- <shared file 1>
- <shared file 2>
- unrelated files

Read first:
1. docs/V5-HANDOVER.md
2. packs/<pack>.md

Required process:
1. Implement only within owned scope
2. Run targeted tests
3. Commit with a clear message
4. Report changed files, tests run, and remaining risks
```

## 5. Worker Done Report Template

When a worker finishes, have it report back in this format:

```text
Done.

Changed files:
- ...

Tests run:
- ...

Commit:
- <commit hash or commit message>

Remaining risks:
- ...

Needs Boss attention:
- yes/no
- if yes: ...
```

## 6. What You Say To Boss After A Worker Finishes

```text
Worker <name> is done. Here is the report:
<paste report>

Decide whether to merge now, queue it, or wait for another branch first.
```

## 7. Merge Checklist For Boss

Boss should do this from the main checkout:

```bash
git checkout main
./scripts/agent-status.sh
git merge --no-ff agent/<task-name>
swift test
```

If there is conflict risk, Boss should merge one worker at a time.

## 8. Beginner Defaults

If unsure:
- run at most 2 workers plus Boss
- avoid assigning two workers to `ContentView.swift`
- avoid assigning two workers to `CellView.swift`
- merge sooner rather than later
- ask Boss to queue work instead of gambling
