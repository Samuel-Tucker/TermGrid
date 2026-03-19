# Pack 021: Skills Storage

**Type:** Feature Spec
**Priority:** Medium
**References:** King Conch Terminal, SkillDeck, Skills-Manager
**URLs:**
- https://github.com/crossoverJie/SkillDeck
- https://github.com/jiweiyeah/Skills-Manager
- https://github.com/xingkongliang/skills-manager
- https://github.com/amandeepmittal/skillsbar

## Problem

Users accumulate coding skills, snippets, prompts, and commands across projects. No centralized way to store, browse, and inject them into terminals.

## Solution

A skills/snippet manager accessible from the toolbar and command palette. Store reusable code snippets, prompts, and shell commands that can be sent to any terminal with one click.

### UI fit:
- **Toolbar button:** Book icon between grid picker and Quick Terminal button
- **Skills panel:** Slides in from the right (like API Locker), 280px wide
- **Command palette entry:** "Open Skills" (global scope)
- **No new per-cell UI** — skills are global, not per-cell

### Panel content:
- **Search bar** at top (filter by name, tag, or content)
- **Category tabs:** All, Prompts, Shell, Code, Custom
- **Skill cards:** Name, description preview, tags, "Send" button
- **Click "Send":** Inserts content into focused cell's compose box (does NOT send — user reviews first)
- **Click skill name:** Expands to show full content with copy button
- **"+ New Skill" button** at bottom

### Skill data model:
```swift
struct Skill: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String
    var content: String        // The actual snippet/prompt/command
    var category: SkillCategory
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
}

enum SkillCategory: String, Codable, CaseIterable {
    case prompt, shell, code, custom
}
```

### Storage:
- `Application Support/TermGrid/skills.json` — array of `Skill` objects
- Import/export: copy skills.json or individual skill as JSON
- No cloud sync in V1

### Insertion behavior:
- "Send to terminal" inserts into focused cell's `ComposeBox` text field
- If no cell focused, show "Focus a terminal first" message
- Multi-line content preserved (ComposeBox supports multi-line)
- Does NOT auto-send — user presses Shift+Enter to send

### Editing:
- Click skill → expand card with edit button
- Edit opens inline editor (name, description, content, category, tags)
- Delete with confirmation
- Drag to reorder (optional, V2)

### Risks:
- Large skills (>10KB content) — truncate preview, lazy-load full content
- No conflict with API Locker panel (both on right side) — mutual exclusion or stacking

### UI impact: Low — toolbar button + right-side panel, no per-cell changes
