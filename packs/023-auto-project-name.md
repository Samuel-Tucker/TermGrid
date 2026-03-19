# Pack 023: Auto-Populate Project Name

**Type:** Feature Spec
**Priority:** Low (quick win)

## Problem

When users set a working directory via the folder picker, the cell label stays empty or whatever was manually typed. Users have to type the project name separately.

## Solution

When a folder path is selected via the directory picker button, auto-populate the cell label with the folder name (last path component) using correct capitalization from the filesystem.

### Implementation:
- In `pickWorkingDirectory()` and `pickExplorerDirectory()` in CellView
- After setting the directory, if cell label is empty, set it to `url.lastPathComponent`
- Only auto-fill if label is currently empty (don't overwrite user-typed labels)
- Use the actual folder name from the filesystem (preserves capitalization)
