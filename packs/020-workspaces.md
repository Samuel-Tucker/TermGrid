# Pack 020: Workspaces

**Type:** Feature Spec
**Priority:** High

## Problem

Users working on multiple projects need separate grid layouts with different terminal configurations. Currently there's only one workspace — switching between projects means manually reconfiguring cells.

## Solution

Add workspace tabs along the top toolbar bar. Each workspace has its own grid layout, cells, terminal sessions, and notes. Users can create, switch, rename, and close workspaces.

### UI:
- Workspace tabs in the toolbar (left side, before grid picker)
- Each tab shows workspace name, click to switch
- "+" button to create new workspace
- Right-click tab for rename/close options
- Active workspace highlighted with accent color

### Data model:
- `WorkspaceStore` manages multiple `Workspace` objects
- Active workspace ID tracked
- Each workspace independent: own cells, grid layout, sessions
- Persisted to disk (one JSON per workspace, or array in workspace.json)

### Session lifecycle:
- Switching workspace: pause/background current sessions, activate target workspace sessions
- Closing workspace: kill all sessions in that workspace, remove from storage
