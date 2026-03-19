# Pack 020: Workspaces

**Type:** Feature Spec
**Priority:** High
**Competitors:** iTerm2 Profiles, Warp Workspaces, tmux sessions

## Problem

Users working on multiple projects need separate grid layouts with different terminal configurations. Currently there's only one workspace — switching between projects means manually reconfiguring cells.

## Solution

Add workspace tabs along the top toolbar. Each workspace has its own grid layout, cells, terminal sessions, notes, and git state. Users can create, switch, rename, and close workspaces.

### UI fit:
- **Workspace tabs** in the toolbar, left side (before grid picker)
- Each tab: workspace name, click to switch, accent underline on active
- **"+" button** after last tab to create new workspace
- **Right-click tab** context menu: Rename, Duplicate, Close
- **Double-click tab** to rename inline
- Active workspace highlighted with `Theme.accent` underline
- Max visible tabs before horizontal scroll: ~5 (overflow scrolls)

### Data model:
- New `WorkspaceCollection` class (replaces single `WorkspaceStore` managing one workspace)
- `WorkspaceCollection` holds `[Workspace]` array + `activeWorkspaceID: UUID`
- Each `Workspace` gets an `id: UUID` and `name: String` field
- `WorkspaceStore` refactored to manage one workspace (owned by `WorkspaceCollection`)
- Persisted as `workspaces.json` containing array of workspaces (migration from single `workspace.json`)

### Session lifecycle:
- **Switching workspace:** Kill all sessions for current workspace, create sessions for target workspace. Scrollback is persisted via Pack 010's `ScrollbackManager`, so switching back restores scrollback.
- **Creating workspace:** New default 2x2 grid with empty cells
- **Closing workspace:** Confirm dialog → kill all sessions → remove from collection → switch to adjacent tab
- **App launch:** Restore last active workspace

### Migration:
- On first launch with new schema: wrap existing `workspace.json` into a single-entry `workspaces.json` with name "Default"
- `SchemaVersion` bump from 1 to 2

### Keyboard shortcuts:
- `Cmd+T` — new workspace
- `Cmd+W` — close current workspace (with confirmation)
- `Cmd+1-9` — switch to workspace by position
- `Cmd+Shift+[` / `Cmd+Shift+]` — previous/next workspace

### Risks:
- Session kill/create on switch is slow for large grids — consider lazy session creation
- Memory: multiple workspaces with scrollback logs can accumulate — cap at 10 workspaces
- Migration must handle corrupt single-workspace files gracefully

### UI impact: Medium — adds tab bar to toolbar, restructures data model
