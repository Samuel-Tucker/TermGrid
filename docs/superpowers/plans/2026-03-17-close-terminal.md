# Close Terminal Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an orange X close button to each terminal cell that kills the terminal, removes the cell, and auto-downsizes the grid.

**Architecture:** Add `removeCell(id:)` + `compactGrid()` to WorkspaceStore, add `onCloseCell` callback + confirmation bar to CellView, wire it in ContentView. No new files.

**Tech Stack:** Swift, SwiftUI

**Spec:** `docs/superpowers/specs/2026-03-17-close-terminal-design.md`

---

## File Map

**Modify:**
- `Sources/TermGrid/Models/WorkspaceStore.swift` — add `removeCell(id:)` and `compactGrid()`
- `Sources/TermGrid/Views/CellView.swift` — add close button, confirmation bar, `onCloseCell` callback
- `Sources/TermGrid/Views/ContentView.swift` — wire `onCloseCell` to kill session + remove cell
- `Tests/TermGridTests/WorkspaceStoreTests.swift` — add removal + compaction tests

---

## Chunk 1: WorkspaceStore removeCell + compactGrid

### Task 1: Cell Removal and Grid Compaction

**Files:**
- Modify: `Sources/TermGrid/Models/WorkspaceStore.swift`
- Test: `Tests/TermGridTests/WorkspaceStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TermGridTests/WorkspaceStoreTests.swift`:

```swift
@Test func removeCellRemovesFromArray() {
    let persistence = PersistenceManager(directory: createTempDir())
    let store = WorkspaceStore(persistence: persistence)
    let cellID = store.workspace.cells[0].id
    let originalCount = store.workspace.cells.count
    store.removeCell(id: cellID)
    #expect(store.workspace.cells.count == originalCount - 1)
    #expect(!store.workspace.cells.contains(where: { $0.id == cellID }))
}

@Test func removeCellStaysAt2x2With3Cells() {
    let persistence = PersistenceManager(directory: createTempDir())
    let store = WorkspaceStore(persistence: persistence)
    store.setGridPreset(.two_by_two) // 4 cells
    let cellToRemove = store.workspace.cells[3].id
    store.removeCell(id: cellToRemove)
    #expect(store.workspace.cells.count == 3)
    #expect(store.workspace.gridLayout == .two_by_two) // stays at 2x2, one empty slot
}

@Test func removeCellCompactsGrid2x2To2x1() {
    let persistence = PersistenceManager(directory: createTempDir())
    let store = WorkspaceStore(persistence: persistence)
    store.setGridPreset(.two_by_two) // 4 cells
    store.removeCell(id: store.workspace.cells[3].id)
    store.removeCell(id: store.workspace.cells[2].id)
    #expect(store.workspace.cells.count == 2)
    #expect(store.workspace.gridLayout == .two_by_one) // compacts to 2x1
}

@Test func removeCellCompactsGrid2x2To1x1() {
    let persistence = PersistenceManager(directory: createTempDir())
    let store = WorkspaceStore(persistence: persistence)
    store.setGridPreset(.two_by_two) // 4 cells
    store.removeCell(id: store.workspace.cells[3].id)
    store.removeCell(id: store.workspace.cells[2].id)
    store.removeCell(id: store.workspace.cells[1].id)
    #expect(store.workspace.cells.count == 1)
    #expect(store.workspace.gridLayout == .one_by_one) // compacts to 1x1
}

@Test func removeCellFrom3x3To3x2() {
    let persistence = PersistenceManager(directory: createTempDir())
    let store = WorkspaceStore(persistence: persistence)
    store.setGridPreset(.three_by_three) // 9 cells
    // Remove 4 cells to get to 5
    for _ in 0..<4 {
        store.removeCell(id: store.workspace.cells.last!.id)
    }
    #expect(store.workspace.cells.count == 5)
    #expect(store.workspace.gridLayout == .three_by_two) // compacts to 3x2 (6 slots)
}

@Test func removeLastCellLeavesEmpty1x1() {
    let persistence = PersistenceManager(directory: createTempDir())
    let store = WorkspaceStore(persistence: persistence)
    store.setGridPreset(.one_by_one) // 1 cell
    store.removeCell(id: store.workspace.cells[0].id)
    #expect(store.workspace.cells.count == 0)
    #expect(store.workspace.gridLayout == .one_by_one)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WorkspaceStoreTests 2>&1 | tail -5`
Expected: compilation error — `removeCell(id:)` not defined

- [ ] **Step 3: Write the implementation**

Add to `Sources/TermGrid/Models/WorkspaceStore.swift`, after the `setGridPreset` method:

```swift
func removeCell(id: UUID) {
    workspace.cells.removeAll { $0.id == id }
    compactGrid()
    scheduleSave()
}

private func compactGrid() {
    let count = workspace.cells.count
    // Prefer wider layouts when cell counts tie
    let preset: GridPreset
    switch count {
    case 7...: preset = .three_by_three  // 9 slots
    case 5...6: preset = .three_by_two   // 6 slots
    case 4:     preset = .two_by_two     // 4 slots
    case 3:     preset = .two_by_two     // 4 slots, one empty
    case 2:     preset = .two_by_one     // 2 slots
    default:    preset = .one_by_one     // 1 slot
    }
    workspace.gridLayout = preset
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WorkspaceStoreTests 2>&1 | tail -10`
Expected: all tests pass including 6 new ones

- [ ] **Step 5: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: all 106+ tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Models/WorkspaceStore.swift Tests/TermGridTests/WorkspaceStoreTests.swift
git commit -m "feat: add removeCell and compactGrid to WorkspaceStore"
```

---

## Chunk 2: CellView Close Button + Confirmation Bar

### Task 2: Close Button and Confirmation Bar in CellView

**Files:**
- Modify: `Sources/TermGrid/Views/CellView.swift`

- [ ] **Step 1: Add `onCloseCell` callback and state**

Add to the CellView properties (after `onUpdateExplorerViewMode`):

```swift
let onCloseCell: () -> Void
```

Add to the `@State` properties:

```swift
@State private var showCloseConfirmation = false
```

- [ ] **Step 2: Add the close button to the header**

In `headerView`, after the last `headerIconButton` call (the "notes" one), add a spacer and the close button:

```swift
            // Gap separator before destructive action
            Spacer().frame(width: 8)

            // Close button — always orange, not part of dock neighbor magnification
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCloseConfirmation = true
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.borderless)
            .scaleEffect(hoveredHeaderButton == "close" ? 1.35 : 1.0)
            .overlay(alignment: .top) {
                Text("Close terminal")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.headerText)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.cellBackground)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: -2)
                    )
                    .offset(y: hoveredHeaderButton == "close" ? -24 : -16)
                    .opacity(hoveredHeaderButton == "close" ? 1 : 0)
            }
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    hoveredHeaderButton = hovering ? "close" : nil
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hoveredHeaderButton)
```

- [ ] **Step 3: Add the confirmation bar**

In the `body` VStack, between `Theme.divider.frame(height: 1)` and the `HStack` (cell body + notes), insert the confirmation bar:

```swift
            // Close confirmation bar
            if showCloseConfirmation {
                HStack(spacing: 0) {
                    // Accent stripe
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: 4)
                        .padding(.vertical, 4)

                    Text("Close this terminal?")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.headerText)
                        .padding(.leading, 10)

                    Spacer()

                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCloseConfirmation = false
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerIcon)

                    Button("Close") {
                        onCloseCell()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.headerBackground)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
```

- [ ] **Step 4: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: compilation error — ContentView needs updating to pass the new `onCloseCell` parameter. This is expected; Task 3 fixes it.

- [ ] **Step 5: Commit (WIP — will compile after Task 3)**

```bash
git add Sources/TermGrid/Views/CellView.swift
git commit -m "feat(wip): add close button and confirmation bar to CellView"
```

---

### Task 3: Wire onCloseCell in ContentView

**Files:**
- Modify: `Sources/TermGrid/Views/ContentView.swift`

- [ ] **Step 1: Add `onCloseCell` to the CellView call**

In `ContentView.gridContent`, in the `CellView(...)` initializer, add after the `onUpdateExplorerViewMode` closure:

```swift
                                    onCloseCell: {
                                        sessionManager.killSession(for: cell.id)
                                        store.removeCell(id: cell.id)
                                    }
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: build succeeds

- [ ] **Step 3: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass (106 existing + 6 new)

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/Views/ContentView.swift
git commit -m "feat: wire onCloseCell to kill session and remove cell"
```

- [ ] **Step 5: Amend the WIP commit from Task 2**

Now that everything compiles, squash the WIP:

```bash
git rebase -i HEAD~2
```

Mark the WIP commit as `fixup` under the ContentView commit. Or alternatively, just leave both commits as-is since they tell a clear story.

Actually, skip the rebase — two commits is fine. The WIP label in the message is the only issue. Let's just leave it.
