# Pack 021: Skills Storage

**Type:** Feature Spec
**Priority:** Medium
**References:** King Conch Terminal, SkillDeck, Skills-Manager

## Problem

Users accumulate coding skills, snippets, and prompts across projects. No centralized way to store, browse, and inject them into terminals.

## Solution

A skills/snippet manager panel accessible from the toolbar or command palette. Store reusable code snippets, prompts, and commands that can be sent to any terminal with one click.

### UI:
- New toolbar button or command palette entry
- Skills panel (sidebar or modal) with categorized list
- Each skill: name, description, content (code/prompt), tags
- Click to send content to focused terminal's compose box
- Search/filter by name or tag

### Storage:
- `~/.termgrid/skills/` directory with JSON or YAML files
- Or embedded in workspace data
- Import/export support

### References:
- https://github.com/crossoverJie/SkillDeck
- https://github.com/jiweiyeah/Skills-Manager
- https://github.com/xingkongliang/skills-manager
- https://github.com/amandeepmittal/skillsbar
