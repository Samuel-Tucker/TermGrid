# Pack 030: Project Notes — Two-Tier Notes System

**Type:** Feature Spec
**Priority:** High
**Depends on:** Pack 016 (Runnable Notebooks — code block execution)

## Problem

The current notes side panel is a single markdown scratchpad per cell. As users accumulate commands, docs, and runbooks, it becomes a wall of text with no organization. Notes aren't stored in the repo, so they can't be shared or version-controlled.

## Solution

Two-tier notes system:

### Tier 1 — Scratch Pad (existing, unchanged)
- Quick side panel (160px) for jotting
- Stored in `Cell.notes` (persisted in workspace JSON)
- Ephemeral, per-panel, private
- No file system involvement

### Tier 2 — Project Notes (new)
- Organized markdown files stored in `.termgrid/notes/` inside the repo
- Full-view display (flips like explorer, replaces terminal area)
- Folder/file browser for navigation
- Runnable code blocks (pack 016)
- Version-controlled, shareable with collaborators

## UI Design

### Notes button becomes a dropdown Menu
Convert existing notes `headerIconButton` to a `Menu`:

```
Menu {
    Button("Scratch Pad")     // toggle side panel (current behavior)
    Button("Project Notes")   // flip to full view
    Divider()
    Button("Hide All")        // close both
}
```

Same icon (`note.text`), same dock-style hover magnification. No new buttons.

### Project Notes full view
Reuse the explorer flip pattern (`if/else` in cellBody):
- Terminal | Explorer | **Project Notes** — three states, one visible at a time
- Header button icon changes to reflect active view

### Project Notes layout
```
+--------------------------------------------------+
| < .termgrid/notes         [+ New Note]  [+ Folder]|
|--------------------------------------------------|
| deploy/                                           |
|   staging.md                                      |
|   production.md                                   |
| commands.md                                       |
| setup.md                                          |
| todo.md                                           |
+--------------------------------------------------+
```

Click a file → opens it in a markdown editor (reuse FilePreviewView pattern with edit mode). Code blocks get hover buttons for Paste/Run (pack 016).

### Scratch pad quick-access dots
- 3-4 tiny dots (4px circles) at bottom of scratch pad
- Click dot → loads a linked project note into scratch pad view
- Right-click dot → "Link to Note..." picker
- `Theme.accent` when active, `Theme.headerIcon` when inactive

### No-directory error state
When no working directory or explorer directory is set:
```
+--------------------------------------------------+
|  [folder.badge.questionmark icon]                 |
|  No directory set for Project Notes               |
|                                                   |
|  [Create .termgrid/notes/ here]                   |
|  [Choose directory...]                            |
+--------------------------------------------------+
```

"Create here" uses `cell.workingDirectory` (or `cell.explorerDirectory` if set).

## Storage

```
<repo>/
  .termgrid/
    notes/
      todo.md
      deploy/
        staging.md
        production.md
      commands.md
```

- Hidden by convention (`.termgrid/`)
- Auto-create `.termgrid/notes/` on first use
- Add `.termgrid/` to existing `.gitignore` check — let user decide if notes are committed
- Each file is plain markdown — editable outside TermGrid

## Data Model

### CellUIState changes
```swift
enum CellNoteMode: String {
    case hidden, scratchPad, projectNotes
}
var noteMode: CellNoteMode = .hidden
```

Replace `showNotes: Bool` with `noteMode`. Backward compat: `showNotes == true` maps to `.scratchPad`.

### Cell changes
```swift
var projectNotesPath: String  // resolved: <explorerDir>/.termgrid/notes/ or <workingDir>/.termgrid/notes/
```

### New model: ProjectNotesModel
Similar to `FileExplorerModel` but scoped to `.termgrid/notes/`:
- `loadNotes()` — list files/folders in the notes directory
- `createNote(named:)` — create new .md file
- `createFolder(named:)` — create subfolder
- `readNote(at:)` / `writeNote(at:content:)` — file I/O
- Auto-creates `.termgrid/notes/` if missing

## Implementation Sequence

1. **CellUIState** — replace `showNotes: Bool` with `noteMode: CellNoteMode` (backward compat)
2. **CellView header** — convert notes button to Menu dropdown
3. **CellView cellBody** — add third branch for project notes view
4. **ProjectNotesModel** — file browser scoped to `.termgrid/notes/`
5. **ProjectNotesView** — folder/file browser + markdown editor (reuse FilePreviewView pattern)
6. **Pack 016 integration** — runnable code blocks in project notes
7. **Scratch pad dots** — quick-access bookmarks linked to project notes
8. **Error state** — no-directory guide with auto-create

## Risks

- Three-way view state (terminal/explorer/notes) adds complexity to cellBody — keep it simple with if/else/else
- `.termgrid/` directory creation needs permission — handle gracefully if repo is read-only
- Large notes directories (100+ files) — cap like explorer (500 items)
- Scratch pad bookmarks are low priority — can ship without them in v1
