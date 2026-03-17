# Pack 005: File Explorer

**Type:** Feature
**Status:** Complete
**Date:** 2026-03-16

## Summary

Added a file explorer to each TermGrid cell, accessible via a page-flip animation. Users can browse files, preview them read-only, and edit inline.

## Changes

### Folder Button → Dropdown Menu
- Folder icon button now opens a `Menu` with two options: "Set Terminal Directory" (existing behavior) and "Set Explorer Directory"
- Menu wrapped in same dock-hover magnification as other header buttons

### Repo Pill Badge
- Appears next to cell label when explorer directory is set (and differs from home)
- Shows shortened path (e.g. `~/repos/TermGrid`)
- Clicking it flips to the explorer view

### Explorer Toggle & Page Flip
- New header button (magnifying glass / terminal icon) toggles between terminal and explorer
- Uses `rotation3DEffect` on Y axis for a card-flip animation
- Only terminal body flips — header, notes, and cell chrome stay fixed

### File Explorer View
- Breadcrumb navigation bar (clickable path components)
- Search bar (filters current directory, case-insensitive)
- Grid view (LazyVGrid with folder/file icons) and list view (rows with file sizes)
- Toggle between grid/list view modes (persisted per cell)
- Hidden files toggle
- "+" menu for creating new files/folders with inline name field
- Folders sorted first, then files, alphabetically

### File Preview & Editor
- Click a file → read-only preview with line numbers
- Image preview (with 10MB size guard)
- Binary file detection
- "Edit" button switches to inline NSTextView editor
- Save/Cancel with unsaved changes confirmation alert

## Data Model
- `ExplorerViewMode` enum (`.grid`, `.list`)
- `Cell.explorerDirectory` (String, default "")
- `Cell.explorerViewMode` (ExplorerViewMode, default .grid)
- Backward-compatible decoding (tolerant `try?` pattern)

## Files Created
- `Sources/TermGrid/Models/FileExplorerModel.swift`
- `Sources/TermGrid/Views/FileExplorerView.swift`
- `Sources/TermGrid/Views/FilePreviewView.swift`
- `Sources/TermGrid/Views/FileEditorView.swift`
- `Tests/TermGridTests/FileExplorerModelTests.swift`

## Files Modified
- `Sources/TermGrid/Models/Workspace.swift`
- `Sources/TermGrid/Models/WorkspaceStore.swift`
- `Sources/TermGrid/Views/CellView.swift`
- `Sources/TermGrid/Views/ContentView.swift`

## Testing
- 53 tests total (17 new for FileExplorerModel)
- Covers: directory listing, search, navigation, file CRUD, binary detection, backward-compatible decoding
