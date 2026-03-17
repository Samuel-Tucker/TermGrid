# Embedded Terminals Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Open Terminal" placeholder in each TermGrid cell with a live embedded terminal session via SwiftTerm.

**Architecture:** Each cell gets a `LocalProcessTerminalView` (SwiftTerm) wrapped in `NSViewRepresentable`. A `TerminalSessionManager` owns all PTY sessions by cell ID, keeping them alive when cells are hidden by grid resize. Sessions are ephemeral (don't survive app restarts). Working directory per cell is set by sending `cd <path>` to the PTY after shell start.

**Tech Stack:** Swift 5.10, SwiftUI, macOS 14+, SwiftTerm, Swift Testing

**Build command:** `swift build 2>&1`

**Test command:** `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks 2>&1`

**Spec:** `docs/superpowers/specs/2026-03-13-embedded-terminals-design.md`

---

## Chunk 1: Data Model & Dependencies

### Task 1: Add SwiftTerm dependency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add SwiftTerm to Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TermGrid",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "TermGrid",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/TermGrid"
        ),
        .testTarget(
            name: "TermGridTests",
            dependencies: ["TermGrid"],
            path: "Tests/TermGridTests"
        )
    ]
)
```

- [ ] **Step 2: Resolve and build**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED (SwiftTerm downloaded and compiled)

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "feat: add SwiftTerm dependency"
```

---

### Task 2: Add workingDirectory to Cell + fix visibleCells

**Files:**
- Modify: `Sources/TermGrid/Models/Workspace.swift`
- Test: `Tests/TermGridTests/WorkspaceTests.swift`

- [ ] **Step 1: Write failing tests for Cell workingDirectory**

Add to `Tests/TermGridTests/WorkspaceTests.swift`:

```swift
@Suite("Cell Codable Tests")
struct CellCodableTests {
    @Test func defaultWorkingDirectoryIsHome() {
        let cell = Cell()
        #expect(cell.workingDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test func roundTripWithWorkingDirectory() throws {
        let cell = Cell(workingDirectory: "/tmp/test")
        let data = try JSONEncoder().encode(cell)
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.workingDirectory == "/tmp/test")
    }

    @Test func decodesLegacyCellWithoutWorkingDirectory() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","label":"test","notes":""}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.label == "test")
        #expect(decoded.workingDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test func decodesTolerantlyWithMissingLabel() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","notes":"hi"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Cell.self, from: data)
        #expect(decoded.label == "")
        #expect(decoded.notes == "hi")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks 2>&1`
Expected: FAIL — `Cell` has no `workingDirectory` property, no custom decoder

- [ ] **Step 3: Implement Cell changes**

Replace the `Cell` struct in `Sources/TermGrid/Models/Workspace.swift`:

```swift
struct Cell: Codable, Identifiable {
    let id: UUID
    var label: String
    var notes: String
    var workingDirectory: String

    init(id: UUID = UUID(), label: String = "", notes: String = "",
         workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.id = id
        self.label = label
        self.notes = notes
        self.workingDirectory = workingDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        workingDirectory = (try? container.decode(String.self, forKey: .workingDirectory))
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }
}
```

- [ ] **Step 4: Fix visibleCells — remove ephemeral padding**

Replace the `visibleCells` computed property in `Workspace`:

```swift
var visibleCells: [Cell] {
    Array(cells.prefix(gridLayout.cellCount))
}
```

Also add normalization to the `Workspace.init(from:)` decoder — after decoding cells, pad if underfilled:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
    gridLayout = (try? container.decode(GridPreset.self, forKey: .gridLayout)) ?? .two_by_two
    var loadedCells = try container.decode([Cell].self, forKey: .cells)
    // Normalize: ensure we have at least gridLayout.cellCount cells
    let needed = gridLayout.cellCount
    if loadedCells.count < needed {
        loadedCells.append(contentsOf: (0..<(needed - loadedCells.count)).map { _ in Cell() })
    }
    cells = loadedCells
}
```

- [ ] **Step 5: Update the visibleCellsPadsWhenTooFew test**

The test at `WorkspaceTests.swift:57-59` creates a Workspace with 1 cell but expects `visibleCells.count == 4`. With the new behavior, `visibleCells` no longer pads — it just takes a prefix. But `Workspace.init` creates the right number of cells, and the decoder normalizes. The test passes a `cells` array directly, so it needs updating:

```swift
@Test func visibleCellsReturnsPrefix() {
    let cells = (0..<9).map { _ in Cell() }
    let workspace = Workspace(gridLayout: .two_by_two, cells: cells)
    #expect(workspace.visibleCells.count == 4)
}

@Test func visibleCellsHandlesUnderfill() {
    // With only 1 cell and a 2x2 grid, visibleCells returns just 1
    let workspace = Workspace(gridLayout: .two_by_two, cells: [Cell()])
    #expect(workspace.visibleCells.count == 1)
}
```

Replace the old `visibleCellsPadsWhenTooFew` and `visibleCellsTruncatesWhenTooMany` tests with these.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks 2>&1`
Expected: ALL PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/TermGrid/Models/Workspace.swift Tests/TermGridTests/WorkspaceTests.swift
git commit -m "feat: add workingDirectory to Cell, fix visibleCells ephemeral UUIDs"
```

---

### Task 3: Add updateWorkingDirectory to WorkspaceStore

**Files:**
- Modify: `Sources/TermGrid/Models/WorkspaceStore.swift`
- Test: `Tests/TermGridTests/WorkspaceStoreTests.swift`

- [ ] **Step 1: Write failing test**

Add to `WorkspaceStoreTests`:

```swift
@Test func updateWorkingDirectory() throws {
    let dir = try H.makeTempDir()
    defer { H.removeTempDir(dir) }
    let store = H.makeStore(directory: dir)
    let cellID = store.workspace.cells[0].id
    store.updateWorkingDirectory("/tmp/myproject", for: cellID)
    #expect(store.workspace.cells[0].workingDirectory == "/tmp/myproject")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks 2>&1`
Expected: FAIL — `updateWorkingDirectory` does not exist

- [ ] **Step 3: Implement updateWorkingDirectory**

Add to `WorkspaceStore` after `updateNotes`:

```swift
func updateWorkingDirectory(_ path: String, for cellID: UUID) {
    guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
    workspace.cells[index].workingDirectory = path
    scheduleSave()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks 2>&1`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Models/WorkspaceStore.swift Tests/TermGridTests/WorkspaceStoreTests.swift
git commit -m "feat: add updateWorkingDirectory to WorkspaceStore"
```

---

## Chunk 2: Terminal Session Layer

### Task 4: Create TerminalSession

**Files:**
- Create: `Sources/TermGrid/Terminal/TerminalSession.swift`

- [ ] **Step 1: Create Terminal directory**

Run: `mkdir -p Sources/TermGrid/Terminal`

- [ ] **Step 2: Write TerminalSession**

Create `Sources/TermGrid/Terminal/TerminalSession.swift`:

```swift
import Foundation
import SwiftTerm

@MainActor
final class TerminalSession {
    let cellID: UUID
    let sessionID: UUID
    let terminalView: LocalProcessTerminalView
    var isRunning: Bool = true

    init(cellID: UUID, workingDirectory: String) {
        self.cellID = cellID
        self.sessionID = UUID()
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: nil,
            execName: nil
        )

        // Set working directory by sending cd command
        let escapedPath = workingDirectory.replacingOccurrences(of: "'", with: "'\\''")
        let cdCommand = "cd '\(escapedPath)' && clear\n"
        terminalView.send(txt: cdCommand)
    }

    func kill() {
        if isRunning {
            terminalView.process?.terminate()
            isRunning = false
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/Terminal/TerminalSession.swift
git commit -m "feat: add TerminalSession wrapper for SwiftTerm"
```

---

### Task 5: Create TerminalSessionManager

**Files:**
- Create: `Sources/TermGrid/Terminal/TerminalSessionManager.swift`

- [ ] **Step 1: Write TerminalSessionManager**

Create `Sources/TermGrid/Terminal/TerminalSessionManager.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class TerminalSessionManager {
    private var sessions: [UUID: TerminalSession] = [:]

    func session(for cellID: UUID) -> TerminalSession? {
        sessions[cellID]
    }

    @discardableResult
    func createSession(for cellID: UUID, workingDirectory: String) -> TerminalSession {
        // Kill existing session for this cell if any
        if let existing = sessions[cellID] {
            existing.kill()
        }
        let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory)
        sessions[cellID] = session
        return session
    }

    func killSession(for cellID: UUID) {
        sessions[cellID]?.kill()
        sessions.removeValue(forKey: cellID)
    }

    func killAll() {
        for session in sessions.values {
            session.kill()
        }
        sessions.removeAll()
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/Terminal/TerminalSessionManager.swift
git commit -m "feat: add TerminalSessionManager for session lifecycle"
```

---

## Chunk 3: View Layer

### Task 6: Create TerminalContainerView (NSViewRepresentable)

**Files:**
- Create: `Sources/TermGrid/Terminal/TerminalContainerView.swift`

- [ ] **Step 1: Write TerminalContainerView**

Create `Sources/TermGrid/Terminal/TerminalContainerView.swift`:

```swift
import SwiftUI
import SwiftTerm

struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = session.terminalView
        view.processDelegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No-op — session identity changes are handled via .id(session.sessionID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let session: TerminalSession

        init(session: TerminalSession) {
            self.session = session
        }

        func processTerminated(_ source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                session.isRunning = false
            }
        }

        func localProcessTerminalView(_ source: LocalProcessTerminalView, titleChanged: String) {
            // No-op for now
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

Note: The `LocalProcessTerminalViewDelegate` protocol methods may differ from what's shown. If the build fails with protocol conformance errors, check the actual SwiftTerm `LocalProcessTerminalViewDelegate` definition and adjust the method signatures. The key method is the one that fires when the process terminates.

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/Terminal/TerminalContainerView.swift
git commit -m "feat: add TerminalContainerView NSViewRepresentable wrapper"
```

---

### Task 7: Rewrite CellView with embedded terminal

**Files:**
- Modify: `Sources/TermGrid/Views/CellView.swift`

- [ ] **Step 1: Rewrite CellView**

Replace the entire contents of `Sources/TermGrid/Views/CellView.swift`:

```swift
import SwiftUI
import AppKit

struct CellView: View {
    let cell: Cell
    let session: TerminalSession?
    let onUpdateLabel: (String) -> Void
    let onUpdateNotes: (String) -> Void
    let onUpdateWorkingDirectory: (String) -> Void
    let onRestartSession: () -> Void

    @State private var isEditingLabel = false
    @State private var labelDraft = ""
    @State private var showNotes = true
    @FocusState private var labelFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Body: terminal + optional notes panel
            HStack(spacing: 0) {
                terminalBody
                if showNotes {
                    Divider()
                    NotesView(notes: cell.notes, onUpdate: onUpdateNotes)
                        .frame(width: 160)
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        HStack {
            if isEditingLabel {
                TextField("Untitled", text: $labelDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($labelFieldFocused)
                    .onSubmit { commitLabel() }
                    .onKeyPress(.escape) {
                        cancelLabel()
                        return .handled
                    }
                    .onChange(of: labelFieldFocused) { _, focused in
                        if !focused && isEditingLabel { commitLabel() }
                    }
                    .onAppear {
                        labelDraft = cell.label
                        labelFieldFocused = true
                    }
            } else {
                Text(cell.label.isEmpty ? "Untitled" : cell.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(cell.label.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        labelDraft = cell.label
                        isEditingLabel = true
                    }
            }

            Spacer()

            // Folder picker button
            Button(action: pickWorkingDirectory) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Set working directory")

            // Notes toggle button
            Button(action: { showNotes.toggle() }) {
                Image(systemName: showNotes ? "note.text" : "note.text.badge.plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help(showNotes ? "Hide notes" : "Show notes")
        }
    }

    // MARK: - Terminal Body

    @ViewBuilder
    private var terminalBody: some View {
        if let session {
            ZStack {
                TerminalContainerView(session: session)
                    .id(session.sessionID)

                if !session.isRunning {
                    // Session ended overlay
                    VStack(spacing: 8) {
                        Text("Session ended")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button("Restart") {
                            onRestartSession()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
        } else {
            // Fallback if no session yet
            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Starting terminal...")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func commitLabel() {
        isEditingLabel = false
        if labelDraft != cell.label {
            onUpdateLabel(labelDraft)
        }
    }

    private func cancelLabel() {
        isEditingLabel = false
    }

    private func pickWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: cell.workingDirectory)
        panel.prompt = "Select"
        panel.message = "Choose a working directory for this terminal"

        if panel.runModal() == .OK, let url = panel.url {
            onUpdateWorkingDirectory(url.path)
        }
    }
}
```

- [ ] **Step 2: Build to check for compile errors**

Run: `swift build 2>&1`
Expected: FAIL — `ContentView` still passes old CellView arguments. That's expected; we fix it in the next task.

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/Views/CellView.swift
git commit -m "feat: rewrite CellView with embedded terminal and notes toggle"
```

---

### Task 8: Update ContentView to pass session manager

**Files:**
- Modify: `Sources/TermGrid/Views/ContentView.swift`

- [ ] **Step 1: Rewrite ContentView**

Replace the entire contents of `Sources/TermGrid/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    var sessionManager: TerminalSessionManager

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: store.workspace.gridLayout.columns
        )
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(store.workspace.visibleCells) { cell in
                    let session = sessionManager.session(for: cell.id)
                    CellView(
                        cell: cell,
                        session: session,
                        onUpdateLabel: { store.updateLabel($0, for: cell.id) },
                        onUpdateNotes: { store.updateNotes($0, for: cell.id) },
                        onUpdateWorkingDirectory: { newPath in
                            store.updateWorkingDirectory(newPath, for: cell.id)
                            sessionManager.createSession(for: cell.id, workingDirectory: newPath)
                        },
                        onRestartSession: {
                            sessionManager.createSession(for: cell.id, workingDirectory: cell.workingDirectory)
                        }
                    )
                    .frame(minHeight: 200)
                    .onAppear {
                        // Create session if none exists for this cell
                        if sessionManager.session(for: cell.id) == nil {
                            sessionManager.createSession(for: cell.id, workingDirectory: cell.workingDirectory)
                        }
                    }
                }
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItem {
                GridPickerView(selection: Binding(
                    get: { store.workspace.gridLayout },
                    set: { store.setGridPreset($0) }
                ))
            }
        }
    }
}
```

- [ ] **Step 2: Build to check — expect fail from TermGridApp**

Run: `swift build 2>&1`
Expected: FAIL — `TermGridApp` doesn't pass `sessionManager` to `ContentView` yet.

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/Views/ContentView.swift
git commit -m "feat: wire ContentView to TerminalSessionManager"
```

---

### Task 9: Update TermGridApp to create and inject session manager

**Files:**
- Modify: `Sources/TermGrid/TermGridApp.swift`

- [ ] **Step 1: Rewrite TermGridApp**

Replace the entire contents of `Sources/TermGrid/TermGridApp.swift`:

```swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct TermGridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()
    @State private var sessionManager = TerminalSessionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        Window("TermGrid", id: "main") {
            ContentView(store: store, sessionManager: sessionManager)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Only flush persistence on background/inactive — do NOT kill sessions
                    if newPhase == .background || newPhase == .inactive {
                        store.flush()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flush()
                    sessionManager.killAll()
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
```

- [ ] **Step 2: Build to verify everything compiles**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests**

Run: `swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks 2>&1`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/TermGridApp.swift
git commit -m "feat: inject TerminalSessionManager into app lifecycle"
```

---

## Chunk 3: Integration & Manual Testing

### Task 10: Smoke test — launch and verify terminals work

- [ ] **Step 1: Launch the app**

Run: `swift run 2>&1 &`

- [ ] **Step 2: Manual verification checklist**

Verify each of these in the running app:

1. **Terminals start** — Each cell shows a live terminal with a shell prompt
2. **Shell is in home directory** — Type `pwd` in a cell, should show home dir
3. **Typing works** — Type commands, see output in the terminal
4. **Label editing** — Click "Untitled" to edit, type a name, click away to commit
5. **Folder picker** — Click the folder icon, pick a directory, terminal should restart with `cd` to that dir
6. **Notes toggle** — Click the notes icon to hide/show the notes panel
7. **Notes editing** — Click "Click to add notes...", type text, press Escape to commit
8. **Grid resize** — Change grid preset in toolbar, verify:
   - Growing: new cells appear with terminals
   - Shrinking: cells hide, resizing back up shows previous sessions still alive
9. **Session ended** — Type `exit` in a terminal, see "Session ended" overlay with Restart button
10. **Restart** — Click Restart button, terminal should start fresh in same working directory
11. **Quit** — Close app, no crashes

- [ ] **Step 3: Fix any issues found during smoke test**

Address any bugs discovered in manual testing. Common issues to watch for:
- SwiftTerm delegate protocol mismatch (method signatures may differ from what's in the plan — check actual SwiftTerm source)
- `LocalProcessTerminalView` may need a non-zero initial frame
- `send(txt:)` method name may differ — check SwiftTerm API for sending text to the terminal
- The `process` property on `LocalProcessTerminalView` may not be directly accessible — check SwiftTerm for how to terminate a running process

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: embedded terminals integration complete"
```
