# File Explorer & Directory Dropdown — Design Spec

**Date:** 2026-03-16
**Status:** Approved

## Overview

Add a file explorer to each TermGrid cell that lives "behind" the terminal — accessible via a page-flip animation. Rework the folder button into a dropdown menu that sets directories for terminal and explorer independently. Show a repo pill badge in the header once an explorer directory is set.

## 1. Folder Button → Dropdown Menu

**Current:** Single `Button` that opens `NSOpenPanel` to set the terminal's working directory.

**New:** SwiftUI `Menu` with two options:
- **"Set Terminal Directory"** — current behavior (opens `NSOpenPanel`, sets `cell.workingDirectory`, restarts terminal session)
- **"Set Explorer Directory"** — opens `NSOpenPanel`, sets new `cell.explorerDirectory` field, file explorer loads that path

**Styling:** `.menuStyle(.borderlessButton)` to match existing icon button look. Same folder icon (`folder`). Dropdown inherits system dark appearance. The `Menu` must be wrapped in the same dock-hover magnification container as other header buttons (scale, blur, tooltip overlay).

**Data model change:**
```swift
struct Cell {
    // existing fields...
    var explorerDirectory: String  // new — defaults to "" (unset)
}
```

When `explorerDirectory` is empty, the explorer uses `workingDirectory` as fallback.

## 2. Repo Pill Badge

**Placement:** In the header `HStack`, immediately after the cell label text.

**Appearance:** Rounded pill with:
- Background: `Theme.cellBorder` (#2E2E35)
- Text: `Theme.accent` (#C4A574)
- Font: `.system(size: 10, design: .monospaced)`
- Padding: 2pt vertical, 8pt horizontal
- Corner radius: 10pt

**Content:** Shortened path using `~` for home directory. E.g. `~/repos/TermGrid`

**Content logic:** Shows the effective explorer directory — `explorerDirectory` if non-empty, otherwise `workingDirectory` — shortened with `~` for the home prefix.

**Behavior:**
- Only visible when the effective explorer directory differs from the home directory
- Clicking the pill flips to the explorer view (convenience shortcut)

## 3. File Explorer Toggle Button

**New header button:** Added to the icon button row (after notes, before or after existing buttons).
- Icon: `doc.text.magnifyingglass` (terminal showing) / `terminal` (explorer showing)
- Same dock-hover magnification style as existing buttons
- Toggles `showExplorer` state on the cell view (`@State`, intentionally ephemeral — cells always start showing terminal on launch)

**Header button IDs:** Update `headerButtonIDs` array to include the new button: `["splitH", "splitV", "folder", "explorer", "notes"]`

## 4. Page Flip Animation

**Mechanism:** `ZStack` containing terminal pane and explorer pane. Toggle uses `rotation3DEffect` on Y axis.

```swift
ZStack {
    // Terminal side
    terminalPane(...)
        .opacity(showExplorer ? 0 : 1)
        .rotation3DEffect(
            .degrees(showExplorer ? -90 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )

    // Explorer side
    FileExplorerView(...)
        .opacity(showExplorer ? 1 : 0)
        .rotation3DEffect(
            .degrees(showExplorer ? 0 : 90),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
}
.animation(.easeInOut(duration: 0.4), value: showExplorer)
```

**Scope:** Only the terminal body area flips. Header, notes panel, and cell chrome remain fixed.

**Split terminal interaction:** The explorer replaces the entire `terminalBody` area (both panes if split). Split controls remain functional but operate on the hidden terminal. Notes panel remains visible alongside the explorer when open.

**Animation tuning note:** The opacity/rotation code above is illustrative. Implementation should use a two-phase approach if the cross-fade looks wrong — rotate front from 0→-90 (hide), then show back and rotate 90→0. Tune during implementation.

## 5. File Explorer View

### 5a. Structure

```
┌─────────────────────────────────┐
│ Breadcrumb: ~ › repos › TermGrid │
├─────────────────────────────────┤
│ 🔍 Search files...    [≡] [⊞]  │
├─────────────────────────────────┤
│                                 │
│   File grid or list view        │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### 5b. Breadcrumb Navigation

- `HStack` of `Button`s with `Image(systemName: "chevron.right")` separators
- Inside `ScrollView(.horizontal, showsIndicators: false)`
- Each path component is clickable (navigates to that directory)
- Current (last) component styled with `Theme.headerText`, ancestors with `Theme.accent`
- Font: `.system(size: 11)`

### 5c. Search Bar

- Rounded rect with search icon + text field
- Background: `Theme.headerBackground` (#1E1E22)
- Filters current directory contents by filename (case-insensitive contains)
- Searches current directory only (non-recursive). Recursive search deferred to V2
- Corner radius: 6pt

### 5d. View Mode Toggle

- Two small icon buttons: `square.grid.2x2` (grid) / `list.bullet` (list)
- Positioned in the search bar row, trailing edge
- Active mode highlighted with `Theme.accent`
- Default: grid view
- Persisted per cell (new field `cell.explorerViewMode`)

### 5e. Grid View (default)

- `LazyVGrid` with `adaptive(minimum: 70)` columns
- Each item: icon (folder/file) + filename label below
- Folders: `NSWorkspace.shared.icon(forFile:)` or SF Symbol `folder.fill` with accent color
- Files: `NSWorkspace.shared.icon(forFile:)` for native file type icons
- Filename: `.system(size: 10)`, `Theme.notesText`, truncated with ellipsis
- Single click navigates into folder / opens file preview
- Folders sorted first, then files, both alphabetical
- Hidden files (dotfiles) hidden by default, with a toggle to show them
- Directories with 500+ items show first 500 with a "Show more" button
- File icons cached per file extension to avoid repeated `NSWorkspace` lookups

### 5f. List View

- `List` or `LazyVStack` with rows
- Each row: icon + filename + trailing metadata (file size or item count for folders)
- Alternating row backgrounds: `Theme.cellBackground` / `Theme.headerBackground`
- Font: `.system(size: 12)` for name, `.system(size: 10)` for metadata

### 5g. New File / New Folder

- "+" button in the search bar area or a context-menu (right-click) option
- Opens a small inline text field for naming
- Creates the file/folder via `FileManager`
- Validates filename (no `/`, no duplicates). Shows inline error if name exists.
- Assumes non-sandboxed execution. Security-scoped bookmarks would be needed for sandbox compatibility.

## 6. File Preview (Read-Only)

**Trigger:** Click a file in the explorer.

**Layout:** Replaces the grid/list view (push navigation within the explorer).

**Structure:**
```
┌─────────────────────────────────┐
│ ← Sources / TermGrid / Theme.swift  [Edit] │
├─────────────────────────────────┤
│                                 │
│   Read-only file content        │
│   Monospace font                │
│   Line numbers (left gutter)    │
│   Scrollable                    │
│                                 │
└─────────────────────────────────┘
```

- Back button (←) returns to directory listing
- Breadcrumb updates to show file path
- Content displayed in `NSTextView` (via `NSViewRepresentable`), `isEditable = false`
- Font: monospace 12pt, `Theme.terminalForeground` color equivalent as SwiftUI Color
- Background: `Theme.headerBackground`
- Non-text files (images): display inline with `Image(nsImage:)`
- Binary files: show "Binary file — cannot preview" message
- Files larger than 1 MB: show truncation warning and load only the first 10,000 lines
- Images larger than 10 MB: show filename and size instead of inline preview

## 7. File Editor (Inline)

**Trigger:** "Edit" button in the preview view.

**Behavior:** Same view transitions from read-only to editable:
- `NSTextView.isEditable` toggled to `true`
- "Edit" button becomes "Save" (accent color) + "Cancel" (secondary)
- Save writes to disk via `FileManager`, then returns to preview mode
- Cancel discards changes and returns to preview mode
- Unsaved changes: if user navigates away (back button, flip to terminal), show a confirmation alert

## 8. Data Model Changes

```swift
enum ExplorerViewMode: String, Codable {
    case grid
    case list
}

struct Cell: Codable, Identifiable {
    // existing...
    var explorerDirectory: String          // new, default ""
    var explorerViewMode: ExplorerViewMode // new, default .grid
}
```

**Backward compatibility:** The existing `Cell.init(from:)` uses tolerant `try?` decoding. New fields must follow the same pattern:
```swift
explorerDirectory = (try? container.decode(String.self, forKey: .explorerDirectory)) ?? ""
explorerViewMode = (try? container.decode(ExplorerViewMode.self, forKey: .explorerViewMode)) ?? .grid
```

`WorkspaceStore` gets two new mutation methods:
- `updateExplorerDirectory(_:for:)`
- `updateExplorerViewMode(_:for:)`

## 9. New Files

| File | Purpose |
|------|---------|
| `Sources/TermGrid/Views/FileExplorerView.swift` | Main explorer container (breadcrumb + search + grid/list) |
| `Sources/TermGrid/Views/FilePreviewView.swift` | Read-only file preview |
| `Sources/TermGrid/Views/FileEditorView.swift` | Editable file view (NSTextView wrapper) |
| `Sources/TermGrid/Models/FileExplorerModel.swift` | Directory listing, search filtering, navigation state |

## 10. Files Modified

| File | Changes |
|------|---------|
| `Workspace.swift` | Add `explorerDirectory`, `explorerViewMode` to `Cell` |
| `WorkspaceStore.swift` | Add mutation methods for new fields |
| `CellView.swift` | Add `showExplorer` state, page flip ZStack, explorer toggle button, repo pill badge, folder Menu dropdown |
| `ContentView.swift` | Wire new callbacks: `onUpdateExplorerDirectory`, `onUpdateExplorerViewMode` |
| `Theme.swift` | Add explorer-specific colors if needed (likely reuse existing) |

## 11. Out of Scope (V1)

- Drag & drop file operations
- File rename (can do in V2)
- Git status indicators on files
- Syntax highlighting (plain monospace for V1)
- Live file watching via FSEvents (manual refresh for V1, add FSEvents in V2)
- Multi-file selection
- Keyboard navigation (flip shortcut, file list nav, back from preview)
- Recursive search
- File rename
