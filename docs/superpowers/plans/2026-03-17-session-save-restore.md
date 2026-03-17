# Pack 010: Session Save & Restore Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist terminal scrollback and layout state to disk. On relaunch, replay scrollback into terminals before starting the shell.

**Architecture:** Add `splitDirection` and `showExplorer` to `Cell` model for layout persistence. Create `ScrollbackManager` for scrollback file I/O. Modify `TerminalSession` for delayed PTY start. Wire save into `WorkspaceStore.flush()` and restore into `ContentView.onAppear`.

**Tech Stack:** Swift, SwiftUI, SwiftTerm (LocalProcessTerminalView, Terminal), Swift Testing

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `Sources/TermGrid/Models/Workspace.swift` | Add `splitDirection: String?` and `showExplorer: Bool` to `Cell` |
| Create | `Sources/TermGrid/Models/ScrollbackManager.swift` | Scrollback file I/O: save, load, cleanup |
| Modify | `Sources/TermGrid/Terminal/TerminalSession.swift` | Delayed PTY start, scrollback history increase, `start()` method |
| Modify | `Sources/TermGrid/Terminal/TerminalSessionManager.swift` | Pass `startImmediately` through create methods |
| Modify | `Sources/TermGrid/Models/WorkspaceStore.swift` | Save scrollback + sync split/explorer state on flush |
| Modify | `Sources/TermGrid/Views/ContentView.swift` | Restore sequence on cell appear |
| Create | `Tests/TermGridTests/ScrollbackManagerTests.swift` | ScrollbackManager file I/O tests |
| Create | `Tests/TermGridTests/SessionRestoreTests.swift` | Cell model + delayed start tests |

---

### Task 1: Add `splitDirection` and `showExplorer` to Cell Model

**Files:**
- Modify: `Sources/TermGrid/Models/Workspace.swift`
- Create: `Tests/TermGridTests/SessionRestoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/TermGridTests/SessionRestoreTests.swift
@testable import TermGrid
import Testing
import Foundation

@Suite("Session Restore Tests")
@MainActor
struct SessionRestoreTests {

    @Test func cellDefaultSplitDirectionIsNil() {
        let cell = Cell()
        #expect(cell.splitDirection == nil)
    }

    @Test func cellDefaultShowExplorerIsFalse() {
        let cell = Cell()
        #expect(cell.showExplorer == false)
    }

    @Test func cellSplitDirectionEncodes() throws {
        var cell = Cell()
        cell.splitDirection = "horizontal"
        cell.showExplorer = true
        let data = try JSONEncoder().encode(cell)
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.splitDirection == "horizontal")
        #expect(decoded.showExplorer == true)
    }

    @Test func cellSplitDirectionNilEncodes() throws {
        let cell = Cell()
        let data = try JSONEncoder().encode(cell)
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.splitDirection == nil)
        #expect(decoded.showExplorer == false)
    }

    @Test func cellDecodesWithoutNewFieldsGracefully() throws {
        // Simulate old workspace JSON without splitDirection/showExplorer
        let json = """
        {"id":"\(UUID().uuidString)","label":"Test","notes":"","workingDirectory":"/tmp","terminalLabel":"","splitTerminalLabel":"","explorerDirectory":"","explorerViewMode":"grid"}
        """
        let data = json.data(using: .utf8)!
        let cell = try JSONDecoder().decode(Cell.self, from: data)
        #expect(cell.splitDirection == nil)
        #expect(cell.showExplorer == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionRestoreTests 2>&1 | tail -20`
Expected: FAIL — `splitDirection` and `showExplorer` not found on `Cell`

- [ ] **Step 3: Add fields to Cell**

In `Sources/TermGrid/Models/Workspace.swift`, add to the `Cell` struct properties (after `explorerViewMode`):

```swift
var splitDirection: String?   // "horizontal", "vertical", or nil
var showExplorer: Bool
```

Update the memberwise init (line 46-48) to include:
```swift
init(id: UUID = UUID(), label: String = "", notes: String = "",
     workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
     terminalLabel: String = "", splitTerminalLabel: String = "",
     explorerDirectory: String = "", explorerViewMode: ExplorerViewMode = .grid,
     splitDirection: String? = nil, showExplorer: Bool = false) {
    // ... existing assignments ...
    self.splitDirection = splitDirection
    self.showExplorer = showExplorer
}
```

Update `init(from decoder:)` (line 60-71) to include:
```swift
splitDirection = try? container.decode(String.self, forKey: .splitDirection)
showExplorer = (try? container.decode(Bool.self, forKey: .showExplorer)) ?? false
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionRestoreTests 2>&1 | tail -20`
Expected: All 5 tests PASS

- [ ] **Step 5: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass (122 existing + 5 new)

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Models/Workspace.swift Tests/TermGridTests/SessionRestoreTests.swift
git commit -m "feat: add splitDirection and showExplorer to Cell model"
```

---

### Task 2: Create ScrollbackManager

**Files:**
- Create: `Sources/TermGrid/Models/ScrollbackManager.swift`
- Create: `Tests/TermGridTests/ScrollbackManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/TermGridTests/ScrollbackManagerTests.swift
@testable import TermGrid
import Testing
import Foundation

@Suite("ScrollbackManager Tests")
@MainActor
struct ScrollbackManagerTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func saveAndLoadPrimary() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        try mgr.save(cellID: cellID, sessionType: .primary, content: "hello world")
        let loaded = mgr.load(cellID: cellID, sessionType: .primary)
        #expect(loaded == "hello world")
    }

    @Test func saveAndLoadSplit() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        try mgr.save(cellID: cellID, sessionType: .split, content: "split content")
        let loaded = mgr.load(cellID: cellID, sessionType: .split)
        #expect(loaded == "split content")
    }

    @Test func loadReturnsNilWhenNoFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let loaded = mgr.load(cellID: UUID(), sessionType: .primary)
        #expect(loaded == nil)
    }

    @Test func cleanupRemovesBothFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        try mgr.save(cellID: cellID, sessionType: .primary, content: "p")
        try mgr.save(cellID: cellID, sessionType: .split, content: "s")
        mgr.cleanup(cellID: cellID)
        #expect(mgr.load(cellID: cellID, sessionType: .primary) == nil)
        #expect(mgr.load(cellID: cellID, sessionType: .split) == nil)
    }

    @Test func cleanupAllRemovesOrphans() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let keep = UUID()
        let orphan = UUID()
        try mgr.save(cellID: keep, sessionType: .primary, content: "keep")
        try mgr.save(cellID: orphan, sessionType: .primary, content: "orphan")
        mgr.cleanupAll(keeping: Set([keep]))
        #expect(mgr.load(cellID: keep, sessionType: .primary) == "keep")
        #expect(mgr.load(cellID: orphan, sessionType: .primary) == nil)
    }

    @Test func saveTruncatesTo5000Lines() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mgr = ScrollbackManager(directory: dir)
        let cellID = UUID()
        let longContent = (0..<6000).map { "line \($0)" }.joined(separator: "\n")
        try mgr.save(cellID: cellID, sessionType: .primary, content: longContent)
        let loaded = mgr.load(cellID: cellID, sessionType: .primary)!
        let lines = loaded.components(separatedBy: "\n")
        #expect(lines.count == 5000)
        // Should keep the LAST 5000 lines (most recent)
        #expect(lines.last == "line 5999")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ScrollbackManagerTests 2>&1 | tail -20`
Expected: FAIL — `ScrollbackManager` type not found

- [ ] **Step 3: Write ScrollbackManager implementation**

```swift
// Sources/TermGrid/Models/ScrollbackManager.swift
import Foundation

@MainActor
final class ScrollbackManager {
    private let directory: URL
    static let maxLines = 5000

    /// Production initializer: uses Application Support/TermGrid/scrollback/
    convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.init(directory: appSupport.appendingPathComponent("TermGrid/scrollback"))
    }

    /// Testable initializer
    init(directory: URL) {
        self.directory = directory
    }

    func save(cellID: UUID, sessionType: SessionType, content: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Truncate to last maxLines lines
        var lines = content.components(separatedBy: "\n")
        if lines.count > Self.maxLines {
            lines = Array(lines.suffix(Self.maxLines))
        }
        let truncated = lines.joined(separator: "\n")

        let url = fileURL(cellID: cellID, sessionType: sessionType)
        try truncated.write(to: url, atomically: true, encoding: .utf8)
    }

    func load(cellID: UUID, sessionType: SessionType) -> String? {
        let url = fileURL(cellID: cellID, sessionType: sessionType)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func cleanup(cellID: UUID) {
        let fm = FileManager.default
        try? fm.removeItem(at: fileURL(cellID: cellID, sessionType: .primary))
        try? fm.removeItem(at: fileURL(cellID: cellID, sessionType: .split))
    }

    func cleanupAll(keeping cellIDs: Set<UUID>) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents {
            let name = url.deletingPathExtension().lastPathComponent
            // Files are named {cellID}-primary.txt or {cellID}-split.txt
            let parts = name.components(separatedBy: "-")
            // UUID has 5 parts separated by hyphens, so the cell ID is the first 5 parts
            // Format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX-primary
            // Split on last hyphen to get UUID and type
            if let lastHyphen = name.lastIndex(of: "-") {
                let uuidString = String(name[name.startIndex..<lastHyphen])
                if let uuid = UUID(uuidString: uuidString), !cellIDs.contains(uuid) {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    private func fileURL(cellID: UUID, sessionType: SessionType) -> URL {
        let suffix = sessionType == .primary ? "primary" : "split"
        return directory.appendingPathComponent("\(cellID.uuidString)-\(suffix).txt")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ScrollbackManagerTests 2>&1 | tail -20`
Expected: All 6 tests PASS

- [ ] **Step 5: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Models/ScrollbackManager.swift Tests/TermGridTests/ScrollbackManagerTests.swift
git commit -m "feat: add ScrollbackManager for scrollback file I/O"
```

---

### Task 3: Modify TerminalSession for Delayed Start + Scrollback Increase

**Files:**
- Modify: `Sources/TermGrid/Terminal/TerminalSession.swift`
- Modify: `Sources/TermGrid/Terminal/TerminalSessionManager.swift`

- [ ] **Step 1: Refactor TerminalSession for delayed start**

Rewrite `TerminalSession.swift` to support two-phase init:

```swift
import Foundation
import SwiftTerm

@MainActor
final class TerminalSession {
    let cellID: UUID
    let sessionID: UUID
    let sessionType: SessionType
    let terminalView: LocalProcessTerminalView
    var isRunning: Bool = true
    private var processStarted = false

    private let shell: String
    private let environment: [String]
    private let workingDirectory: String

    init(cellID: UUID, workingDirectory: String, sessionType: SessionType = .primary,
         environment: [String]? = nil, startImmediately: Bool = true) {
        self.cellID = cellID
        self.sessionID = UUID()
        self.sessionType = sessionType
        self.workingDirectory = workingDirectory
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        self.shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        var env = environment ?? Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TERMGRID_CELL_ID=\(cellID.uuidString)")
        env.append("TERMGRID_SESSION_TYPE=\(sessionType.rawValue)")
        self.environment = env

        terminalView.nativeBackgroundColor = Theme.terminalBackground
        terminalView.nativeForegroundColor = Theme.terminalForeground
        terminalView.caretColor = Theme.terminalCursor

        if startImmediately {
            start()
        }
    }

    func start() {
        guard !processStarted else { return }
        processStarted = true
        isRunning = true
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: environment,
            execName: nil,
            currentDirectory: workingDirectory
        )
    }

    /// Feed scrollback text into the terminal emulator (before start).
    /// Also increases scrollback history to 5000 lines.
    func feedScrollback(_ text: String) {
        // Increase scrollback buffer to 5000 lines (SwiftTerm default is 500)
        let terminal = terminalView.getTerminal()
        terminal.changeHistorySize(5000)

        // Feed restored content
        terminalView.feed(text: text)
        terminalView.feed(text: "\n── restored scrollback ──\n")
    }

    func send(_ text: String) {
        guard isRunning else { return }
        terminalView.send(txt: text)
    }

    func kill() {
        if isRunning {
            terminalView.terminate()
            isRunning = false
        }
    }

    /// Read the current scrollback buffer as text.
    func getScrollbackText() -> String? {
        let terminal = terminalView.getTerminal()
        let data = terminal.getBufferAsData(kind: .normal, encoding: .utf8)
        return String(data: data, encoding: .utf8)
    }
}
```

**Key changes:**
- Store `shell`, `environment`, `workingDirectory` as properties
- `startImmediately` parameter (default `true` for backward compat)
- New `start()` method
- New `feedScrollback(_ text:)` method — sets scrollback to 5000, feeds text + separator
- New `getScrollbackText()` method — reads buffer via `.normal` kind

**IMPORTANT runtime note:** `feedScrollback` calls `terminalView.getTerminal()` and `terminalView.feed(text:)`. The terminal object is created lazily when the view is laid out via `setupOptions`. If the view hasn't been laid out yet (frame is .zero, not in view hierarchy), the terminal may not exist. The implementer must verify this works and potentially trigger layout first by adding the view to the hierarchy before calling `feedScrollback`. If `getTerminal()` crashes on nil terminal, the restore sequence in ContentView must ensure the view is rendered (via `TerminalContainerView`) before calling `feedScrollback`.

- [ ] **Step 2: Update TerminalSessionManager create methods**

In `TerminalSessionManager.swift`, add `startImmediately` parameter to both create methods:

```swift
@discardableResult
func createSession(for cellID: UUID, workingDirectory: String,
                   startImmediately: Bool = true) -> TerminalSession {
    if let existing = sessions[cellID] {
        existing.kill()
    }
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory,
                                   sessionType: .primary, environment: buildEnvironment(),
                                   startImmediately: startImmediately)
    sessions[cellID] = session
    return session
}

@discardableResult
func createSplitSession(for cellID: UUID, workingDirectory: String,
                         direction: SplitDirection,
                         startImmediately: Bool = true) -> TerminalSession {
    if let existing = splitSessions[cellID] {
        existing.kill()
    }
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory,
                                   sessionType: .split, environment: buildEnvironment(),
                                   startImmediately: startImmediately)
    splitSessions[cellID] = session
    splitDirections[cellID] = direction
    return session
}
```

- [ ] **Step 3: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass (existing behavior unchanged due to default `startImmediately: true`)

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/Terminal/TerminalSession.swift Sources/TermGrid/Terminal/TerminalSessionManager.swift
git commit -m "feat: add delayed PTY start and scrollback APIs to TerminalSession"
```

---

### Task 4: Wire Save Sequence into WorkspaceStore.flush()

**Files:**
- Modify: `Sources/TermGrid/Models/WorkspaceStore.swift`

- [ ] **Step 1: Add ScrollbackManager and TerminalSessionManager references**

`WorkspaceStore` needs access to session manager and scrollback manager to save state. Add properties:

```swift
@MainActor
@Observable
final class WorkspaceStore {
    var workspace: Workspace
    private let persistence: PersistenceManager
    private let scrollbackManager: ScrollbackManager
    private var saveTask: Task<Void, Never>?
    var sessionManager: TerminalSessionManager?
    var cellUIStates: [UUID: CellUIState]?
```

Update the init:
```swift
init(persistence: PersistenceManager = PersistenceManager(),
     scrollbackManager: ScrollbackManager = ScrollbackManager()) {
    self.persistence = persistence
    self.scrollbackManager = scrollbackManager
    // ... existing load logic ...
}
```

- [ ] **Step 2: Add saveScrollback method**

```swift
func saveScrollback() {
    guard let sessionManager else { return }

    for cell in workspace.visibleCells {
        // Sync split direction from session manager
        if let idx = workspace.cells.firstIndex(where: { $0.id == cell.id }) {
            if let dir = sessionManager.splitDirection(for: cell.id) {
                workspace.cells[idx].splitDirection = dir == .horizontal ? "horizontal" : "vertical"
            } else {
                workspace.cells[idx].splitDirection = nil
            }

            // Sync showExplorer from CellUIState
            if let uiState = cellUIStates?[cell.id] {
                workspace.cells[idx].showExplorer = uiState.showExplorer
            }
        }

        // Save primary scrollback
        if let session = sessionManager.session(for: cell.id),
           let text = session.getScrollbackText(), !text.isEmpty {
            try? scrollbackManager.save(cellID: cell.id, sessionType: .primary, content: text)
        }

        // Save split scrollback
        if let splitSession = sessionManager.splitSession(for: cell.id),
           let text = splitSession.getScrollbackText(), !text.isEmpty {
            try? scrollbackManager.save(cellID: cell.id, sessionType: .split, content: text)
        }
    }
}
```

- [ ] **Step 3: Call saveScrollback in flush()**

Update `flush()` to call `saveScrollback()` before saving workspace:

```swift
func flush() {
    saveTask?.cancel()
    saveTask = nil
    saveScrollback()
    do {
        try persistence.save(workspace)
    } catch {
        print("[TermGrid] Save failed: \(error)")
    }
}
```

- [ ] **Step 4: Add cleanup on cell removal**

Update `removeCell(id:)`:

```swift
func removeCell(id: UUID) {
    workspace.cells.removeAll { $0.id == id }
    scrollbackManager.cleanup(cellID: id)
    compactGrid()
    scheduleSave()
}
```

- [ ] **Step 5: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass. Existing WorkspaceStore tests still work because `sessionManager` is nil by default (saveScrollback is a no-op).

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Models/WorkspaceStore.swift
git commit -m "feat: wire scrollback save into WorkspaceStore.flush()"
```

---

### Task 5: Wire Restore Sequence into ContentView

**Files:**
- Modify: `Sources/TermGrid/Views/ContentView.swift`
- Modify: `Sources/TermGrid/TermGridApp.swift`

- [ ] **Step 1: Add ScrollbackManager to app and pass references**

In `TermGridApp.swift`, add:
```swift
@State private var scrollbackManager = ScrollbackManager()
```

Pass `sessionManager` and `cellUIStates` references to `store` in the `.onAppear`:
```swift
.onAppear {
    store.sessionManager = sessionManager
    store.cellUIStates = cellUIStates  // Need to sync this
    // ... existing code ...
}
```

Note: `cellUIStates` is a `@State` dictionary in ContentView. Since `store.cellUIStates` is a reference, we need to update it when `cellUIStates` changes. The simplest approach: set it once, and since both the store and ContentView reference the same `CellUIState` objects (reference types), mutations are shared.

Actually, a cleaner approach: pass the scrollbackManager to ContentView and have ContentView handle the restore. The store just needs `sessionManager` for save.

- [ ] **Step 2: Update ContentView onAppear for restore**

In `ContentView.swift`, add `scrollbackManager` property and update the `.onAppear` on each cell:

Add property:
```swift
var scrollbackManager: ScrollbackManager
```

Replace the existing `.onAppear` on each cell (line 90-93):

```swift
.onAppear {
    if sessionManager.session(for: cell.id) == nil {
        // Restore split if persisted
        if let dirStr = cell.splitDirection {
            let dir: SplitDirection = dirStr == "horizontal" ? .horizontal : .vertical
            let splitSession = sessionManager.createSplitSession(
                for: cell.id, workingDirectory: cell.workingDirectory,
                direction: dir, startImmediately: false
            )
            if let text = scrollbackManager.load(cellID: cell.id, sessionType: .split) {
                splitSession.feedScrollback(text)
            }
            splitSession.start()
        }

        // Create primary session
        let hasScrollback = scrollbackManager.load(cellID: cell.id, sessionType: .primary)
        let session = sessionManager.createSession(
            for: cell.id, workingDirectory: cell.workingDirectory,
            startImmediately: hasScrollback == nil
        )
        if let text = hasScrollback {
            session.feedScrollback(text)
            session.start()
        }

        // Restore explorer state
        if cell.showExplorer {
            uiState(for: cell.id).showExplorer = true
        }
    }
}
```

- [ ] **Step 3: Pass scrollbackManager from TermGridApp**

Update `TermGridApp.swift` to pass the manager and wire store references:

```swift
ContentView(store: store, sessionManager: sessionManager, vault: vault,
            docsManager: docsManager, scrollbackManager: scrollbackManager)
```

In `.onAppear`, wire store references:
```swift
store.sessionManager = sessionManager
```

- [ ] **Step 4: Clean up orphaned scrollback on launch**

In ContentView's `.onAppear` (the body-level one, not per-cell), add cleanup:

```swift
.onAppear {
    // ... existing code ...
    // Clean up orphaned scrollback files
    let activeCellIDs = Set(store.workspace.cells.map(\.id))
    scrollbackManager.cleanupAll(keeping: activeCellIDs)
}
```

- [ ] **Step 5: Sync cellUIStates to store for save**

In ContentView, after the `.onChange(of: store.workspace.visibleCells.map(\.id))` modifier, add a way for the store to access cellUIStates. The simplest: pass the reference in `.onAppear`:

```swift
store.cellUIStates = cellUIStates
```

Since `CellUIState` is a reference type and the dictionary values are shared, the store reads the same objects.

- [ ] **Step 6: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

Note: The restore sequence involves SwiftTerm's `feed(text:)` and `getTerminal()` which require a laid-out view. If `feedScrollback` fails because the terminal isn't initialized yet, the implementer should defer feeding to after the view appears in the hierarchy (e.g., using `DispatchQueue.main.async` or `.task` modifier). This is a runtime concern that must be verified manually.

- [ ] **Step 7: Commit**

```bash
git add Sources/TermGrid/Views/ContentView.swift Sources/TermGrid/TermGridApp.swift
git commit -m "feat: wire session restore sequence on app launch"
```

---

### Task 6: Manual Verification & Edge Cases

- [ ] **Step 1: Build and launch**

Run: `swift build 2>&1 | tail -5`
Launch app, type some commands in terminals, then quit and relaunch.

Verify:
- Scrollback text appears with `── restored scrollback ──` separator
- New shell prompt appears below the separator
- Split configurations are restored
- Explorer state is restored
- Grid layout is preserved (existing behavior)

- [ ] **Step 2: Test edge cases**

- Close a cell, quit, relaunch → orphaned scrollback should be cleaned up
- Empty terminal (no scrollback) → should start fresh without separator
- Terminal with alternate screen active (vim/less) → scrollback should capture normal buffer, not alternate screen

- [ ] **Step 3: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 4: Final commit if cleanup needed**

```bash
git add -A
git commit -m "chore: Pack 010 cleanup and final adjustments"
```
