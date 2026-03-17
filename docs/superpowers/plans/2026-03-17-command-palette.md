# Pack 012: Command Palette Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Cmd+Shift+P` command palette with architectural prerequisites (CellUIState, focusedCellID, cell-scoped notifications) that unblock Packs 010 and 011.

**Architecture:** Lift private `@State` panel toggles from CellView into a shared `CellUIState` observable per cell. Track the focused cell at the window level. Build a command registry + overlay palette mounted on the Window scene.

**Tech Stack:** Swift, SwiftUI, AppKit (NSEvent monitors, responder chain), Swift Testing

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `Sources/TermGrid/Models/CellUIState.swift` | Per-cell observable UI state (showNotes, showExplorer, showGit) |
| Create | `Sources/TermGrid/CommandPalette/AppCommand.swift` | Command types: `AppCommand` struct, `CommandScope`, `CommandContext` |
| Create | `Sources/TermGrid/CommandPalette/CommandRegistry.swift` | Registry holding all commands, populated at init |
| Create | `Sources/TermGrid/CommandPalette/CommandPaletteView.swift` | Overlay UI: search field, filtered list, keyboard nav |
| Modify | `Sources/TermGrid/Views/CellView.swift` | Replace `@State showNotes/showExplorer` with `CellUIState`, pass `cellID` to NotesView |
| Modify | `Sources/TermGrid/Views/ContentView.swift` | Own `[UUID: CellUIState]` dict, add `focusedCellID`, pass state to CellView |
| Modify | `Sources/TermGrid/Views/NotesView.swift` | Add `cellID` param, filter `.focusNotesPanel` on cell ID |
| Modify | `Sources/TermGrid/Views/FileExplorerView.swift` | Add `cellID` param for cell-scoped notification filtering |
| Modify | `Sources/TermGrid/TermGridApp.swift` | Add Commands menu with Cmd+Shift+P shortcut |
| Create | `Tests/TermGridTests/CellUIStateTests.swift` | CellUIState default values and toggle behavior |
| Create | `Tests/TermGridTests/CommandRegistryTests.swift` | Registry filtering by scope, availability, search |

---

### Task 1: Create CellUIState Observable

**Files:**
- Create: `Sources/TermGrid/Models/CellUIState.swift`
- Create: `Tests/TermGridTests/CellUIStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/TermGridTests/CellUIStateTests.swift
@testable import TermGrid
import Testing

@Suite("CellUIState Tests")
@MainActor
struct CellUIStateTests {

    @Test func defaultValues() {
        let state = CellUIState()
        #expect(state.showNotes == true)
        #expect(state.showExplorer == false)
        #expect(state.showGit == false)
    }

    @Test func toggleShowNotes() {
        let state = CellUIState()
        state.showNotes = false
        #expect(state.showNotes == false)
    }

    @Test func toggleShowExplorer() {
        let state = CellUIState()
        state.showExplorer = true
        #expect(state.showExplorer == true)
    }

    @Test func toggleShowGit() {
        let state = CellUIState()
        state.showGit = true
        #expect(state.showGit == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CellUIStateTests 2>&1 | tail -20`
Expected: FAIL — `CellUIState` type not found

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/TermGrid/Models/CellUIState.swift
import Foundation
import Observation

@MainActor
@Observable
final class CellUIState {
    var showNotes: Bool = true
    var showExplorer: Bool = false
    var showGit: Bool = false
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CellUIStateTests 2>&1 | tail -20`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Models/CellUIState.swift Tests/TermGridTests/CellUIStateTests.swift
git commit -m "feat: add CellUIState observable model (Pack 012 prereq 1)"
```

---

### Task 2: Lift State from CellView to CellUIState

**Files:**
- Modify: `Sources/TermGrid/Views/ContentView.swift`
- Modify: `Sources/TermGrid/Views/CellView.swift`

- [ ] **Step 1: Add CellUIState dictionary to ContentView**

In `ContentView.swift`, add a `@State` dictionary after the existing `@State` properties (line 9):

```swift
@State private var cellUIStates: [UUID: CellUIState] = [:]
```

- [ ] **Step 2: Pre-populate CellUIState dictionary on appear**

Add an `.onChange` modifier to ContentView's `body` (alongside existing modifiers) that ensures every visible cell has a `CellUIState`. This avoids mutating `@State` during body evaluation:

```swift
.onChange(of: store.workspace.visibleCells.map(\.id), initial: true) { _, cellIDs in
    for id in cellIDs where cellUIStates[id] == nil {
        cellUIStates[id] = CellUIState()
    }
}
```

- [ ] **Step 3: Pass CellUIState to CellView**

In `ContentView.swift`, update the `CellView(...)` call (line 34) to add a new `uiState` parameter. Use a force-unwrap since `.onChange(initial: true)` guarantees population:

```swift
CellView(
    cell: cell,
    uiState: cellUIStates[cell.id] ?? CellUIState(),
    session: session,
    ...
```

Note: The `?? CellUIState()` fallback handles the first render before `.onChange(initial: true)` fires. The fallback is transient — `.onChange` will replace it immediately.

- [ ] **Step 3: Update CellView to accept and use CellUIState**

In `CellView.swift`:

a) Add new property after `let onCloseCell: () -> Void` (line 20):
```swift
let uiState: CellUIState
```

b) Remove these two `@State` lines (lines 24-25):
```swift
// DELETE: @State private var showNotes = true
// DELETE: @State private var showExplorer = false
```

c) Replace all references to `showNotes` with `uiState.showNotes` and `showExplorer` with `uiState.showExplorer` throughout the file. Key locations:
- Line 85: `if showNotes {` → `if uiState.showNotes {`
- Line 161: `showExplorer ? "Show Terminal" : "Show Explorer"` → `uiState.showExplorer ? ...`
- Line 162: `showExplorer.toggle()` → `uiState.showExplorer.toggle()`
- Line 211: `showExplorer` in icon name → `uiState.showExplorer`
- Line 212: `showExplorer` in label → `uiState.showExplorer`
- Line 214: `showExplorer.toggle()` → `uiState.showExplorer.toggle()`
- Line 220: `showNotes` in icon name → `uiState.showNotes`
- Line 221: `showNotes` in label → `uiState.showNotes`
- Line 222: `showNotes.toggle()` → `uiState.showNotes.toggle()`
- Line 326: `showExplorer` opacity → `uiState.showExplorer`
- Line 328-329: `showExplorer` rotation → `uiState.showExplorer`
- Line 338: `showExplorer` opacity → `uiState.showExplorer`
- Line 340: `showExplorer` rotation → `uiState.showExplorer`
- Line 345: `showExplorer` animation value → `uiState.showExplorer`
- Line 539: `if showNotes {` → `if uiState.showNotes {`

- [ ] **Step 4: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All 112 existing tests still pass. (Build may show warnings for now — that's fine as long as tests pass.)

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Views/CellView.swift Sources/TermGrid/Views/ContentView.swift
git commit -m "refactor: lift showNotes/showExplorer from CellView @State to CellUIState"
```

---

### Task 3: Add Focused Cell Tracking

**Files:**
- Modify: `Sources/TermGrid/Views/ContentView.swift`

- [ ] **Step 1: Add focusedCellID state to ContentView**

In `ContentView.swift`, add after the `cellUIStates` property:

```swift
@State private var focusedCellID: UUID? = nil
@State private var focusMonitor: Any? = nil
```

- [ ] **Step 2: Add focus tracking monitor**

Add `.onAppear` and `.onDisappear` modifiers to the `body` in ContentView (after `.onAppear` at line 140):

```swift
.onAppear {
    sessionManager.vaultKeys = vault.decryptedKeys
    focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
        DispatchQueue.main.async {
            updateFocusedCell()
        }
        return event
    }
}
.onDisappear {
    if let monitor = focusMonitor {
        NSEvent.removeMonitor(monitor)
        focusMonitor = nil
    }
}
```

Note: replace the existing `.onAppear` at line 140-142 — merge the `sessionManager.vaultKeys` assignment into the new one.

- [ ] **Step 3: Add updateFocusedCell helper**

Add at the bottom of ContentView:

```swift
private func updateFocusedCell() {
    guard let window = NSApp.keyWindow,
          let responder = window.firstResponder as? NSView else { return }

    // Walk up from the first responder to find which cell's terminal or compose view it belongs to
    var view: NSView? = responder
    while let v = view {
        // Check if this view contains a terminal — that means it's a cell container
        if let termView = findTerminalView(in: v) {
            // Find which cell this terminal belongs to
            for cell in store.workspace.visibleCells {
                if let session = sessionManager.session(for: cell.id),
                   session.terminalView === termView {
                    focusedCellID = cell.id
                    return
                }
                if let splitSession = sessionManager.splitSession(for: cell.id),
                   splitSession.terminalView === termView {
                    focusedCellID = cell.id
                    return
                }
            }
        }
        view = v.superview
    }
}

private func findTerminalView(in view: NSView) -> NSView? {
    if view is SwiftTerm.LocalProcessTerminalView {
        return view
    }
    for subview in view.subviews {
        if let found = findTerminalView(in: subview) {
            return found
        }
    }
    return nil
}
```

- [ ] **Step 4: Add imports**

Add `import AppKit` and `import SwiftTerm` at the top of ContentView.swift (required for NSEvent, NSView, and LocalProcessTerminalView).

- [ ] **Step 5: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests still pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Views/ContentView.swift
git commit -m "feat: add focusedCellID tracking via NSEvent monitor (Pack 012 prereq 2)"
```

---

### Task 4: Fix Cell-Scoped Notes Notification

**Files:**
- Modify: `Sources/TermGrid/Views/NotesView.swift`
- Modify: `Sources/TermGrid/Views/CellView.swift`

- [ ] **Step 1: Add cellID parameter to NotesView**

In `NotesView.swift`, add `cellID` as the first parameter (after line 6):

```swift
struct NotesView: View {
    let cellID: UUID
    let notes: String
    let onUpdate: (String) -> Void
```

- [ ] **Step 2: Filter notification on cell ID**

In `NotesView.swift`, replace the `.onReceive` block (line 63-67):

```swift
.onReceive(NotificationCenter.default.publisher(for: .focusNotesPanel)) { notification in
    guard let targetID = notification.object as? UUID, targetID == cellID else { return }
    if !isEditing {
        startEdit()
    }
}
```

- [ ] **Step 3: Update call site in CellView**

In `CellView.swift`, update the NotesView instantiation (line 87):

```swift
NotesView(cellID: cell.id, notes: cell.notes, onUpdate: onUpdateNotes)
```

- [ ] **Step 4: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests still pass

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Views/NotesView.swift Sources/TermGrid/Views/CellView.swift
git commit -m "fix: scope focusNotesPanel notification to target cell (Pack 012 prereq 3)"
```

---

### Task 5: Create Command Types

**Files:**
- Create: `Sources/TermGrid/CommandPalette/AppCommand.swift`

- [ ] **Step 1: Create the CommandPalette directory**

```bash
mkdir -p Sources/TermGrid/CommandPalette
```

- [ ] **Step 2: Write AppCommand types**

```swift
// Sources/TermGrid/CommandPalette/AppCommand.swift
import Foundation

enum CommandScope {
    case global
    case cell
}

struct CommandContext {
    let focusedCellID: UUID?
    let cellUIState: CellUIState?
    let store: WorkspaceStore
    let sessionManager: TerminalSessionManager
}

struct AppCommand: Identifiable {
    let id: String
    let title: String
    let icon: String
    let scope: CommandScope
    var isAvailable: (CommandContext) -> Bool = { _ in true }
    let action: (CommandContext) -> Void
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/CommandPalette/AppCommand.swift
git commit -m "feat: add AppCommand types for command palette registry"
```

---

### Task 6: Create Command Registry

**Files:**
- Create: `Sources/TermGrid/CommandPalette/CommandRegistry.swift`
- Create: `Tests/TermGridTests/CommandRegistryTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/TermGridTests/CommandRegistryTests.swift
@testable import TermGrid
import Testing

@Suite("CommandRegistry Tests")
@MainActor
struct CommandRegistryTests {

    @Test func registryContainsAllCommands() {
        let registry = CommandRegistry()
        // Should have at least the 9 initial commands
        #expect(registry.commands.count >= 9)
    }

    @Test func filterBySearchEmpty() {
        let registry = CommandRegistry()
        let results = registry.filter(query: "")
        #expect(results.count == registry.commands.count)
    }

    @Test func filterBySearchSubstring() {
        let registry = CommandRegistry()
        let results = registry.filter(query: "notes")
        #expect(results.contains(where: { $0.title.localizedCaseInsensitiveContains("notes") }))
        #expect(!results.isEmpty)
    }

    @Test func filterBySearchNoMatch() {
        let registry = CommandRegistry()
        let results = registry.filter(query: "xyznonexistent")
        #expect(results.isEmpty)
    }

    @Test func globalCommandsAlwaysAvailable() {
        let registry = CommandRegistry()
        let globals = registry.commands.filter { $0.scope == .global }
        #expect(!globals.isEmpty)
        // Global commands should be available even without a focused cell
        let context = CommandContext(
            focusedCellID: nil,
            cellUIState: nil,
            store: WorkspaceStore(persistence: PersistenceManager(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))),
            sessionManager: TerminalSessionManager()
        )
        for cmd in globals {
            #expect(cmd.isAvailable(context))
        }
    }

    @Test func cellCommandsAvailableWithFocusedCell() {
        let registry = CommandRegistry()
        let cellCmds = registry.commands.filter { $0.scope == .cell }
        #expect(!cellCmds.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CommandRegistryTests 2>&1 | tail -20`
Expected: FAIL — `CommandRegistry` type not found

- [ ] **Step 3: Write CommandRegistry implementation**

```swift
// Sources/TermGrid/CommandPalette/CommandRegistry.swift
import Foundation

@MainActor
final class CommandRegistry {
    let commands: [AppCommand]

    init() {
        commands = Self.buildCommands()
    }

    func filter(query: String) -> [AppCommand] {
        guard !query.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    func availableCommands(for context: CommandContext) -> [AppCommand] {
        commands.filter { cmd in
            switch cmd.scope {
            case .global:
                return cmd.isAvailable(context)
            case .cell:
                return context.focusedCellID != nil && cmd.isAvailable(context)
            }
        }
    }

    private static func buildCommands() -> [AppCommand] {
        [
            AppCommand(
                id: "toggle-notes",
                title: "Toggle Notes",
                icon: "note.text",
                scope: .cell,
                action: { ctx in ctx.cellUIState?.showNotes.toggle() }
            ),
            AppCommand(
                id: "toggle-explorer",
                title: "Toggle File Explorer",
                icon: "doc.text.magnifyingglass",
                scope: .cell,
                action: { ctx in ctx.cellUIState?.showExplorer.toggle() }
            ),
            AppCommand(
                id: "set-terminal-directory",
                title: "Set Terminal Directory",
                icon: "folder",
                scope: .cell,
                action: { ctx in
                    guard let cellID = ctx.focusedCellID else { return }
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Select"
                    panel.message = "Choose a working directory for this terminal"
                    if panel.runModal() == .OK, let url = panel.url {
                        ctx.store.updateWorkingDirectory(url.path, for: cellID)
                        ctx.sessionManager.createSession(for: cellID, workingDirectory: url.path)
                    }
                }
            ),
            AppCommand(
                id: "set-explorer-directory",
                title: "Set Explorer Directory",
                icon: "folder.badge.gearshape",
                scope: .cell,
                action: { ctx in
                    guard let cellID = ctx.focusedCellID else { return }
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Select"
                    panel.message = "Choose a directory for the file explorer"
                    if panel.runModal() == .OK, let url = panel.url {
                        ctx.store.updateExplorerDirectory(url.path, for: cellID)
                    }
                }
            ),
            AppCommand(
                id: "new-file",
                title: "New File",
                icon: "doc.badge.plus",
                scope: .cell,
                isAvailable: { ctx in ctx.cellUIState?.showExplorer == true },
                action: { ctx in
                    NotificationCenter.default.post(
                        name: .commandPaletteNewFile,
                        object: ctx.focusedCellID
                    )
                }
            ),
            AppCommand(
                id: "new-folder",
                title: "New Folder",
                icon: "folder.badge.plus",
                scope: .cell,
                isAvailable: { ctx in ctx.cellUIState?.showExplorer == true },
                action: { ctx in
                    NotificationCenter.default.post(
                        name: .commandPaletteNewFolder,
                        object: ctx.focusedCellID
                    )
                }
            ),
            AppCommand(
                id: "toggle-hidden-files",
                title: "Show/Hide Hidden Files",
                icon: "eye",
                scope: .cell,
                isAvailable: { ctx in ctx.cellUIState?.showExplorer == true },
                action: { ctx in
                    NotificationCenter.default.post(
                        name: .commandPaletteToggleHidden,
                        object: ctx.focusedCellID
                    )
                }
            ),
            AppCommand(
                id: "switch-grid-layout",
                title: "Switch Grid Layout",
                icon: "square.grid.2x2",
                scope: .global,
                action: { _ in
                    // This will be handled by focusing the grid picker
                    // For now, post a notification
                    NotificationCenter.default.post(
                        name: .commandPaletteSwitchGrid,
                        object: nil
                    )
                }
            ),
            AppCommand(
                id: "toggle-api-locker",
                title: "Toggle API Locker",
                icon: "lock.fill",
                scope: .global,
                action: { _ in
                    NotificationCenter.default.post(
                        name: .commandPaletteToggleAPILocker,
                        object: nil
                    )
                }
            ),
        ]
    }
}

// MARK: - Notification Names for Command Palette Actions

extension Notification.Name {
    static let commandPaletteNewFile = Notification.Name("TermGrid.commandPalette.newFile")
    static let commandPaletteNewFolder = Notification.Name("TermGrid.commandPalette.newFolder")
    static let commandPaletteToggleHidden = Notification.Name("TermGrid.commandPalette.toggleHidden")
    static let commandPaletteSwitchGrid = Notification.Name("TermGrid.commandPalette.switchGrid")
    static let commandPaletteToggleAPILocker = Notification.Name("TermGrid.commandPalette.toggleAPILocker")
}
```

- [ ] **Step 4: Add `import AppKit`** (required for NSOpenPanel in CommandRegistry)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CommandRegistryTests 2>&1 | tail -20`
Expected: All 6 tests PASS

- [ ] **Step 6: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass (112 existing + 10 new)

- [ ] **Step 7: Commit**

```bash
git add Sources/TermGrid/CommandPalette/CommandRegistry.swift Tests/TermGridTests/CommandRegistryTests.swift
git commit -m "feat: add CommandRegistry with initial 9 commands"
```

---

### Task 7: Build Command Palette UI

**Files:**
- Create: `Sources/TermGrid/CommandPalette/CommandPaletteView.swift`

- [ ] **Step 1: Write CommandPaletteView**

```swift
// Sources/TermGrid/CommandPalette/CommandPaletteView.swift
import SwiftUI

struct CommandPaletteView: View {
    let registry: CommandRegistry
    let context: CommandContext
    let onDismiss: () -> Void

    @State private var searchQuery = ""
    @State private var selectedIndex = 0

    private var filteredCommands: [AppCommand] {
        let available = registry.availableCommands(for: context)
        guard !searchQuery.isEmpty else { return available }
        return available.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Context header
            HStack {
                if let cellID = context.focusedCellID,
                   let cell = context.store.workspace.visibleCells.first(where: { $0.id == cellID }) {
                    Text("Cell: \(cell.label.isEmpty ? "Untitled" : cell.label)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.accent)
                } else {
                    Text("Global")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.headerIcon)
                }
                Spacer()
                Text("⌘⇧P")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.composePlaceholder)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.composePlaceholder)
                TextField("Type a command...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.headerText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.headerBackground)

            Theme.divider.frame(height: 1)

            // Command list
            if filteredCommands.isEmpty {
                VStack(spacing: 6) {
                    Text("No matching commands")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.composePlaceholder)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                commandRow(command, isSelected: index == selectedIndex)
                                    .id(command.id)
                                    .onTapGesture {
                                        executeCommand(command)
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                    .onChange(of: selectedIndex) { _, newIndex in
                        if newIndex < filteredCommands.count {
                            proxy.scrollTo(filteredCommands[newIndex].id)
                        }
                    }
                }
            }
        }
        .frame(width: 400, maxHeight: 300)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.cellBackground)
                .shadow(color: .black.opacity(0.5), radius: 20)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.cellBorder, lineWidth: 1)
        )
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredCommands.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex < filteredCommands.count {
                executeCommand(filteredCommands[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onChange(of: searchQuery) { _, _ in
            selectedIndex = 0
        }
    }

    @ViewBuilder
    private func commandRow(_ command: AppCommand, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Theme.accent : Theme.headerIcon)
                .frame(width: 20)

            Text(command.title)
                .font(.system(size: 12))
                .foregroundColor(Theme.headerText)

            Spacer()

            Text(command.scope == .global ? "Global" : "Cell")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.composePlaceholder)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Theme.cellBorder)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Theme.accent.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private func executeCommand(_ command: AppCommand) {
        command.action(context)
        onDismiss()
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/CommandPalette/CommandPaletteView.swift
git commit -m "feat: add CommandPaletteView overlay UI"
```

---

### Task 8: Wire Palette into App

**Files:**
- Modify: `Sources/TermGrid/TermGridApp.swift`
- Modify: `Sources/TermGrid/Views/ContentView.swift`

- [ ] **Step 1: Add palette state and registry to ContentView**

The palette overlay lives inside ContentView (not TermGridApp) because ContentView owns `cellUIStates`, `focusedCellID`, `store`, and `sessionManager`. No need to lift state to the parent.

In `ContentView.swift`, add after existing `@State` properties:

```swift
@State private var showCommandPalette = false
@State private var commandRegistry = CommandRegistry()
```

- [ ] **Step 2: Mount palette overlay in ContentView body**

In `ContentView.swift`, wrap the existing `HStack` body in a `ZStack` and add the palette overlay:

```swift
var body: some View {
    ZStack {
        HStack(spacing: 0) {
            gridContent
            if showAPILocker {
                Divider()
                APILockerPanel(vault: vault, docsManager: docsManager)
            }
        }
        .background(Theme.appBackground)
        // ... existing toolbar and modifiers ...

        // Command palette overlay
        if showCommandPalette {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    showCommandPalette = false
                }

            CommandPaletteView(
                registry: commandRegistry,
                context: CommandContext(
                    focusedCellID: focusedCellID,
                    cellUIState: focusedCellID.flatMap { cellUIStates[$0] },
                    store: store,
                    sessionManager: sessionManager
                ),
                onDismiss: { showCommandPalette = false }
            )
        }
    }
    .animation(.easeOut(duration: 0.15), value: showCommandPalette)
}
```

- [ ] **Step 3: Add Commands menu with keyboard shortcut in TermGridApp**

In `TermGridApp.swift`, add a `commands` modifier to the `body` (after `.defaultSize()`):

```swift
.commands {
    CommandGroup(after: .toolbar) {
        Button("Command Palette") {
            NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
    }
}
```

In `ContentView.swift`, add a receiver:
```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in
    showCommandPalette.toggle()
}
```

Add the notification name (in CommandRegistry.swift or AppCommand.swift):
```swift
static let toggleCommandPalette = Notification.Name("TermGrid.toggleCommandPalette")
```

- [ ] **Step 4: Handle runtime keyboard shortcut fallback**

If `Cmd+Shift+P` doesn't fire when terminal NSView is first responder, add a fallback NSEvent monitor. In ContentView's `.onAppear` (alongside the existing focus monitor):

```swift
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.modifierFlags.contains([.command, .shift]),
       event.charactersIgnoringModifiers == "p" {
        showCommandPalette.toggle()
        return nil
    }
    return event
}
```

Note: This can be combined with the existing focus tracking monitor from Task 3 into a single `.keyDown` handler, with a separate `.leftMouseDown` monitor for focus tracking only.

- [ ] **Step 5: Wire notification-based commands in ContentView**

In `ContentView.swift`, add notification receivers for global commands:

```swift
.onReceive(NotificationCenter.default.publisher(for: .commandPaletteToggleAPILocker)) { _ in
    showAPILocker.toggle()
}
```

- [ ] **Step 6: Add cellID to FileExplorerView and wire notifications**

Multiple `FileExplorerView` instances exist simultaneously (one per visible cell). Without cell ID filtering, notifications fire on ALL cells. Fix:

a) Add `let cellID: UUID` to `FileExplorerView`:
```swift
struct FileExplorerView: View {
    let cellID: UUID
    let rootPath: String
    let viewMode: ExplorerViewMode
    let onViewModeChange: (ExplorerViewMode) -> Void
```

b) Update the call site in CellView (line 333-337):
```swift
FileExplorerView(
    cellID: cell.id,
    rootPath: cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory,
    viewMode: cell.explorerViewMode,
    onViewModeChange: onUpdateExplorerViewMode
)
```

c) Update FileExplorerView's init to accept `cellID`:
```swift
init(cellID: UUID, rootPath: String, viewMode: ExplorerViewMode, onViewModeChange: @escaping (ExplorerViewMode) -> Void) {
    self.cellID = cellID
    self.rootPath = rootPath
    ...
```

d) Add notification receivers that filter by cellID:
```swift
.onReceive(NotificationCenter.default.publisher(for: .commandPaletteNewFile)) { notification in
    guard let targetID = notification.object as? UUID, targetID == cellID else { return }
    newItemIsFolder = false
    newItemName = ""
    isCreatingNewItem = true
}
.onReceive(NotificationCenter.default.publisher(for: .commandPaletteNewFolder)) { notification in
    guard let targetID = notification.object as? UUID, targetID == cellID else { return }
    newItemIsFolder = true
    newItemName = ""
    isCreatingNewItem = true
}
.onReceive(NotificationCenter.default.publisher(for: .commandPaletteToggleHidden)) { notification in
    guard let targetID = notification.object as? UUID, targetID == cellID else { return }
    model.showHiddenFiles.toggle()
    model.loadContents()
}
```

- [ ] **Step 7: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/TermGrid/TermGridApp.swift Sources/TermGrid/Views/ContentView.swift Sources/TermGrid/Views/FileExplorerView.swift Sources/TermGrid/Views/CellView.swift Sources/TermGrid/CommandPalette/AppCommand.swift
git commit -m "feat: wire command palette into app with Cmd+Shift+P shortcut"
```

---

### Task 9: Manual Verification

- [ ] **Step 1: Build and launch the app**

Run: `swift build 2>&1 | tail -5`
Then launch manually to verify:
- `Cmd+Shift+P` opens the palette
- Context header shows the focused cell label
- Typing filters commands
- Up/Down arrows navigate, Enter executes
- Escape and click-outside dismiss
- Toggle Notes / Toggle Explorer work correctly
- Clicking a cell changes the focused cell context

- [ ] **Step 2: Run full test suite one final time**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass (112 existing + 10 new = 122)

- [ ] **Step 3: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "chore: Pack 012 cleanup and final adjustments"
```
