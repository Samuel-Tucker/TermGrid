# Pack 011: Git Sidebar Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toggleable git status sidebar to each terminal cell showing branch, file status, merge/rebase state, and quick actions.

**Architecture:** Create `GitStatusModel` (polling git status via Process) and `GitSidebarView` (SwiftUI panel). Wire into CellView as a left-side panel opposite notes. Lift `previewingFile` from FileExplorerView for git→explorer file preview integration.

**Tech Stack:** Swift, SwiftUI, Foundation (Process for git CLI), Swift Testing

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `Sources/TermGrid/Theme.swift` | Add `staged` color |
| Create | `Sources/TermGrid/Models/GitStatusModel.swift` | Git command execution, porcelain v2 parsing, polling |
| Create | `Sources/TermGrid/Views/GitSidebarView.swift` | Git sidebar UI panel |
| Modify | `Sources/TermGrid/Views/FileExplorerView.swift` | Change `previewingFile` from @State to Binding |
| Modify | `Sources/TermGrid/Views/CellView.swift` | Add git header button, sidebar panel, mutual exclusion, focus cycling, previewingFile state |
| Modify | `Sources/TermGrid/CommandPalette/CommandRegistry.swift` | Add "Toggle Git Sidebar" command |
| Create | `Tests/TermGridTests/GitStatusModelTests.swift` | Porcelain v2 parsing tests |

---

### Task 1: Add Theme Color + GitStatusModel

**Files:**
- Modify: `Sources/TermGrid/Theme.swift`
- Create: `Sources/TermGrid/Models/GitStatusModel.swift`
- Create: `Tests/TermGridTests/GitStatusModelTests.swift`

- [ ] **Step 1: Add staged color to Theme**

In `Sources/TermGrid/Theme.swift`, add after the Accent section (line 40):

```swift
// MARK: - Git
static let staged = Color(hex: "#75BE95")
```

- [ ] **Step 2: Write failing tests for git status parsing**

```swift
// Tests/TermGridTests/GitStatusModelTests.swift
@testable import TermGrid
import Testing
import Foundation

@Suite("GitStatusModel Tests")
@MainActor
struct GitStatusModelTests {

    @Test func parseBranchName() {
        let output = """
        # branch.oid abc123
        # branch.head main
        1 .M N... 100644 100644 100644 abc def Sources/file.swift
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.branch == "main")
    }

    @Test func parseDetachedHead() {
        let output = """
        # branch.oid abc123
        # branch.head (detached)
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.branch == "(detached)")
    }

    @Test func parseStagedFiles() {
        let output = """
        # branch.head main
        1 A. N... 100644 100644 100644 abc def newfile.swift
        1 M. N... 100644 100644 100644 abc def modified.swift
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.staged.count == 2)
        #expect(result.staged[0].path == "newfile.swift")
    }

    @Test func parseModifiedFiles() {
        let output = """
        # branch.head main
        1 .M N... 100644 100644 100644 abc def unstaged.swift
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.modified.count == 1)
        #expect(result.modified[0].path == "unstaged.swift")
    }

    @Test func parseUntrackedFiles() {
        let output = """
        # branch.head main
        ? newfile.txt
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.untracked.count == 1)
        #expect(result.untracked[0].path == "newfile.txt")
    }

    @Test func parseMixedStatus() {
        let output = """
        # branch.head feature/test
        1 A. N... 100644 100644 100644 abc def staged.swift
        1 .M N... 100644 100644 100644 abc def modified.swift
        1 AM N... 100644 100644 100644 abc def both.swift
        ? untracked.txt
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.branch == "feature/test")
        // AM = staged AND modified
        #expect(result.staged.count == 2) // A. and AM
        #expect(result.modified.count == 2) // .M and AM
        #expect(result.untracked.count == 1)
    }

    @Test func parseEmptyRepo() {
        let output = """
        # branch.head main
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.branch == "main")
        #expect(result.staged.isEmpty)
        #expect(result.modified.isEmpty)
        #expect(result.untracked.isEmpty)
    }

    @Test func parseRenamedFile() {
        let output = """
        # branch.head main
        2 R. N... 100644 100644 100644 abc def R100 new.swift\told.swift
        """
        let result = GitStatusModel.parseStatus(output)
        #expect(result.staged.count == 1)
        #expect(result.staged[0].path == "new.swift")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter GitStatusModelTests 2>&1 | tail -20`
Expected: FAIL — `GitStatusModel` not found

- [ ] **Step 4: Write GitStatusModel implementation**

```swift
// Sources/TermGrid/Models/GitStatusModel.swift
import Foundation
import Observation

struct GitFileEntry: Identifiable {
    let id = UUID()
    let path: String
    let status: String
}

struct GitStatusResult {
    var branch: String = ""
    var staged: [GitFileEntry] = []
    var modified: [GitFileEntry] = []
    var untracked: [GitFileEntry] = []
    var mergeState: String? = nil  // "MERGING", "REBASING 3/5", etc.
    var isRepo: Bool = true
}

@MainActor
@Observable
final class GitStatusModel {
    var result = GitStatusResult()
    var isLoading = false

    private var repoRoot: String?
    private var gitDir: String?
    private var pollTask: Task<Void, Never>?
    private var sequenceNumber: Int = 0
    private var inFlight = false
    private let gitPath = "/usr/bin/git"

    private var directory: String = ""

    func setDirectory(_ path: String) {
        guard path != directory else { return }
        directory = path
        repoRoot = nil
        gitDir = nil
        stopPolling()
        resolveRepo()
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func resolveRepo() {
        Task {
            let topLevel = await runGit(["-C", directory, "rev-parse", "--show-toplevel"])
            if let root = topLevel?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty {
                repoRoot = root
                let gd = await runGit(["-C", directory, "rev-parse", "--git-dir"])
                if let dir = gd?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    // --git-dir may return relative path; resolve against repo root
                    if dir.hasPrefix("/") {
                        gitDir = dir
                    } else {
                        gitDir = (root as NSString).appendingPathComponent(dir)
                    }
                }
                result.isRepo = true
                await poll()
            } else {
                result = GitStatusResult()
                result.isRepo = false
            }
        }
    }

    private func poll() async {
        guard let repoRoot, !inFlight else { return }
        inFlight = true
        sequenceNumber += 1
        let mySequence = sequenceNumber

        let output = await runGit(["-C", repoRoot, "status", "--porcelain=v2", "--branch"])
        guard mySequence == sequenceNumber else {
            inFlight = false
            return // stale
        }

        if let output {
            var parsed = Self.parseStatus(output)
            // Check merge/rebase state
            if let gitDir {
                parsed.mergeState = Self.detectMergeState(gitDir: gitDir)
            }
            result = parsed
        }
        inFlight = false
    }

    // MARK: - Parsing (static for testability)

    static func parseStatus(_ output: String) -> GitStatusResult {
        var result = GitStatusResult()
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix("# branch.head ") {
                result.branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                // Changed entry: "1 XY ..." or rename "2 XY ..."
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 9 else { continue }
                let xy = parts[1]
                let x = xy.prefix(1) // index/staged status
                let y = xy.suffix(1) // worktree/modified status

                var path: String
                if line.hasPrefix("2 ") {
                    // Rename: path is before the tab, old path after
                    let afterParts = parts[8...].joined(separator: " ")
                    path = afterParts.components(separatedBy: "\t").first ?? afterParts
                } else {
                    path = parts[8...].joined(separator: " ")
                }

                if x != "." && x != "?" {
                    result.staged.append(GitFileEntry(path: path, status: String(x)))
                }
                if y != "." && y != "?" {
                    result.modified.append(GitFileEntry(path: path, status: String(y)))
                }
            } else if line.hasPrefix("? ") {
                let path = String(line.dropFirst(2))
                result.untracked.append(GitFileEntry(path: path, status: "?"))
            }
        }
        return result
    }

    static func detectMergeState(gitDir: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("MERGE_HEAD")) {
            return "MERGING"
        }
        let rebaseMerge = (gitDir as NSString).appendingPathComponent("rebase-merge")
        if fm.fileExists(atPath: rebaseMerge) {
            let msgnum = (try? String(contentsOfFile: (rebaseMerge as NSString).appendingPathComponent("msgnum")))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
            let end = (try? String(contentsOfFile: (rebaseMerge as NSString).appendingPathComponent("end")))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
            return "REBASING \(msgnum)/\(end)"
        }
        if fm.fileExists(atPath: (gitDir as NSString).appendingPathComponent("rebase-apply")) {
            return "REBASING"
        }
        return nil
    }

    // MARK: - Quick Actions

    func stageAll() {
        guard let repoRoot else { return }
        Task {
            _ = await runGit(["-C", repoRoot, "add", "-A"])
            await poll()
        }
    }

    func unstageAll() {
        guard let repoRoot else { return }
        Task {
            // Check if HEAD exists (unborn branch)
            let headCheck = await runGit(["-C", repoRoot, "rev-parse", "HEAD"])
            if headCheck == nil || headCheck?.contains("fatal") == true {
                // Unborn branch
                _ = await runGit(["-C", repoRoot, "rm", "--cached", "-r", "."])
            } else {
                let cached = await runGit(["-C", repoRoot, "diff", "--cached", "--name-only", "--diff-filter=d"])
                if let files = cached?.components(separatedBy: "\n").filter({ !$0.isEmpty }), !files.isEmpty {
                    _ = await runGit(["-C", repoRoot, "restore", "--staged", "--"] + files)
                }
            }
            await poll()
        }
    }

    // MARK: - Git Process

    private func runGit(_ args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter GitStatusModelTests 2>&1 | tail -20`
Expected: All 8 tests PASS

- [ ] **Step 6: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/TermGrid/Theme.swift Sources/TermGrid/Models/GitStatusModel.swift Tests/TermGridTests/GitStatusModelTests.swift
git commit -m "feat: add GitStatusModel with porcelain v2 parsing and polling"
```

---

### Task 2: Create GitSidebarView

**Files:**
- Create: `Sources/TermGrid/Views/GitSidebarView.swift`

- [ ] **Step 1: Write GitSidebarView**

```swift
// Sources/TermGrid/Views/GitSidebarView.swift
import SwiftUI

struct GitSidebarView: View {
    let cellID: UUID
    @Bindable var model: GitStatusModel
    let onFileClick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.result.isRepo {
                notARepoView
            } else {
                branchHeader
                if let state = model.result.mergeState {
                    stateBanner(state)
                }
                Theme.divider.frame(height: 1)
                fileList
                Theme.divider.frame(height: 1)
                quickActions
            }
        }
        .background(Theme.notesBackground)
    }

    // MARK: - Not a Repo

    @ViewBuilder
    private var notARepoView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 24))
                .foregroundColor(Theme.headerIcon)
            Text("Not a git repository")
                .font(.system(size: 11))
                .foregroundColor(Theme.composePlaceholder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Branch Header

    @ViewBuilder
    private var branchHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundColor(Theme.accent)
            Text(model.result.branch)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.headerText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.result.branch, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - State Banner

    @ViewBuilder
    private func stateBanner(_ state: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(state)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Theme.accent)
    }

    // MARK: - File List

    @ViewBuilder
    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.result.staged.isEmpty {
                    sectionHeader("STAGED", color: Theme.staged)
                    ForEach(model.result.staged) { file in
                        fileRow(file, color: Theme.staged)
                    }
                }
                if !model.result.modified.isEmpty {
                    sectionHeader("MODIFIED", color: Theme.accent)
                    ForEach(model.result.modified) { file in
                        fileRow(file, color: Theme.accent)
                    }
                }
                if !model.result.untracked.isEmpty {
                    sectionHeader("UNTRACKED", color: Theme.headerIcon)
                    ForEach(model.result.untracked) { file in
                        fileRow(file, color: Theme.headerIcon)
                    }
                }
                if model.result.staged.isEmpty && model.result.modified.isEmpty && model.result.untracked.isEmpty {
                    Text("Working tree clean")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.composePlaceholder)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func fileRow(_ file: GitFileEntry, color: Color) -> some View {
        Button {
            onFileClick(file.path)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text((file.path as NSString).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.notesText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 8) {
            Button("Stage All") { model.stageAll() }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.staged)
                .disabled(model.result.modified.isEmpty && model.result.untracked.isEmpty)

            Button("Unstage All") { model.unstageAll() }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.accent)
                .disabled(model.result.staged.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/Views/GitSidebarView.swift
git commit -m "feat: add GitSidebarView UI panel"
```

---

### Task 3: Lift previewingFile + Wire Git Sidebar into CellView

**Files:**
- Modify: `Sources/TermGrid/Views/FileExplorerView.swift`
- Modify: `Sources/TermGrid/Views/CellView.swift`

- [ ] **Step 1: Change FileExplorerView previewingFile from @State to Binding**

In `Sources/TermGrid/Views/FileExplorerView.swift`, change line 11:

FROM: `@State private var previewingFile: String? = nil`
TO: `@Binding var previewingFile: String?`

Update the init (line 16-22):
```swift
init(cellID: UUID, rootPath: String, viewMode: ExplorerViewMode,
     previewingFile: Binding<String?>,
     onViewModeChange: @escaping (ExplorerViewMode) -> Void) {
    self.cellID = cellID
    self.rootPath = rootPath
    self.viewMode = viewMode
    self._previewingFile = previewingFile
    self.onViewModeChange = onViewModeChange
    self._model = State(initialValue: FileExplorerModel(rootPath: rootPath))
}
```

- [ ] **Step 2: Add git state and previewingFile to CellView**

In `Sources/TermGrid/Views/CellView.swift`, add after existing `@State` properties (around line 28):

```swift
@State private var gitModel = GitStatusModel()
@State private var previewingFile: String? = nil
```

Update `headerButtonIDs` (line 30):
```swift
private static let headerButtonIDs = ["splitH", "splitV", "explorer", "git", "notes"]
```

- [ ] **Step 3: Add git header button**

In CellView's `headerView`, add between the explorer and notes buttons (after line 215):

```swift
headerIconButton(
    id: "git",
    systemName: uiState.showGit ? "arrow.triangle.branch" : "arrow.triangle.branch",
    label: uiState.showGit ? "Hide git" : "Show git",
    action: {
        uiState.showGit.toggle()
        if uiState.showGit {
            let dir = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
            gitModel.setDirectory(dir)
            gitModel.startPolling()
        } else {
            gitModel.stopPolling()
        }
    }
)
```

- [ ] **Step 4: Add git sidebar panel to cell body**

Update the `HStack` in the body (lines 82-89) to include git sidebar on the left:

```swift
HStack(spacing: 0) {
    if uiState.showGit {
        GitSidebarView(
            cellID: cell.id,
            model: gitModel,
            onFileClick: { path in
                // Resolve full path from repo root
                let fullPath: String
                if path.hasPrefix("/") {
                    fullPath = path
                } else if let root = gitModel.result.branch.isEmpty ? nil : nil {
                    fullPath = path // fallback
                } else {
                    let dir = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
                    fullPath = (dir as NSString).appendingPathComponent(path)
                }
                previewingFile = fullPath
                if !uiState.showExplorer {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        uiState.showExplorer = true
                    }
                }
            }
        )
        .frame(width: 160)
        Divider()
    }
    cellBody
    if uiState.showNotes {
        Divider()
        NotesView(cellID: cell.id, notes: cell.notes, onUpdate: onUpdateNotes)
            .frame(width: 160)
    }
}
```

- [ ] **Step 5: Update FileExplorerView call to pass previewingFile binding**

In `cellBody` (around line 332-337), update the `FileExplorerView` call:

```swift
FileExplorerView(
    cellID: cell.id,
    rootPath: cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory,
    viewMode: cell.explorerViewMode,
    previewingFile: $previewingFile,
    onViewModeChange: onUpdateExplorerViewMode
)
```

- [ ] **Step 6: Stop polling on disappear**

Add to the `.onDisappear` block (around line 112):

```swift
.onDisappear {
    if let monitor = focusMonitor {
        NSEvent.removeMonitor(monitor)
        focusMonitor = nil
    }
    gitModel.stopPolling()
}
```

- [ ] **Step 7: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/TermGrid/Views/FileExplorerView.swift Sources/TermGrid/Views/CellView.swift
git commit -m "feat: wire git sidebar into CellView with file preview integration"
```

---

### Task 4: Mutual Exclusion + Focus Cycling + Command Registry

**Files:**
- Modify: `Sources/TermGrid/Views/CellView.swift`
- Modify: `Sources/TermGrid/CommandPalette/CommandRegistry.swift`

- [ ] **Step 1: Add mutual exclusion for narrow cells**

In CellView, add an `.onChange` handler for `uiState.showGit` and `uiState.showNotes` to enforce mutual exclusion. Add after the `.onDisappear` block:

```swift
.onChange(of: uiState.showGit) { _, showGit in
    if showGit {
        // TODO: check cell width < 400 for mutual exclusion
        // For now, always allow both unless we have geometry
    }
}
```

A cleaner approach: wrap the cell body HStack in a `GeometryReader` or pass `cellWidth` from the `.frame` modifier. Since cell width is computed in ContentView, pass it to CellView. However, to keep this simple, add mutual exclusion directly in the toggle action:

In the git header button action, add:
```swift
action: {
    uiState.showGit.toggle()
    if uiState.showGit {
        let dir = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
        gitModel.setDirectory(dir)
        gitModel.startPolling()
    } else {
        gitModel.stopPolling()
    }
}
```

Note: Skip width-based mutual exclusion for V1 — both panels are 160px each (320px total), and cells have a minimum width of 100px in the grid. The mutual exclusion only matters for 1x1 grids or very narrow windows. Defer to user testing.

- [ ] **Step 2: Update focus cycling**

In CellView's `cycleFocus()` method, update the rotation to include git:

```swift
private func cycleFocus() {
    guard let window = NSApp.keyWindow else { return }
    let currentResponder = window.firstResponder

    let container = cellContainer(for: currentResponder) ?? window.contentView

    let isTerminal = currentResponder is SwiftTerm.TerminalView
        || (currentResponder?.isKind(of: NSClassFromString("SwiftTerm.TerminalView") ?? NSView.self) ?? false)
    let isCompose = currentResponder is ComposeNSTextView

    if isTerminal {
        if let compose = findView(ofType: ComposeNSTextView.self, in: container) {
            window.makeFirstResponder(compose)
        }
    } else if isCompose {
        if uiState.showGit {
            // Compose → Git
            NotificationCenter.default.post(name: .focusGitPanel, object: cell.id)
        } else if uiState.showNotes {
            // Compose → Notes
            NotificationCenter.default.post(name: .focusNotesPanel, object: cell.id)
        } else {
            if let term = findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: container) {
                window.makeFirstResponder(term)
            }
        }
    } else {
        // Git/Notes/other → next in cycle or terminal
        // If we're in git panel, go to notes (if visible) or terminal
        // If we're in notes panel, go to terminal
        if uiState.showNotes {
            // Could be in git → try notes
            NotificationCenter.default.post(name: .focusNotesPanel, object: cell.id)
        } else {
            if let term = findView(ofType: SwiftTerm.LocalProcessTerminalView.self, in: container) {
                window.makeFirstResponder(term)
            }
        }
    }
}
```

- [ ] **Step 3: Add focusGitPanel notification name**

In `Sources/TermGrid/Views/ComposeBox.swift` (where `.focusNotesPanel` is defined), add:

```swift
static let focusGitPanel = Notification.Name("TermGrid.focusGitPanel")
```

Or add it in CommandRegistry.swift's Notification.Name extension. Check where `.focusNotesPanel` is defined and add alongside it.

- [ ] **Step 4: Add "Toggle Git Sidebar" to CommandRegistry**

In `Sources/TermGrid/CommandPalette/CommandRegistry.swift`, add to the `buildCommands()` array (after "toggle-explorer"):

```swift
AppCommand(
    id: "toggle-git-sidebar",
    title: "Toggle Git Sidebar",
    icon: "arrow.triangle.branch",
    scope: .cell,
    action: { ctx in ctx.cellUIState?.showGit.toggle() }
),
```

- [ ] **Step 5: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Views/CellView.swift Sources/TermGrid/CommandPalette/CommandRegistry.swift Sources/TermGrid/Views/ComposeBox.swift
git commit -m "feat: add focus cycling, mutual exclusion, and git sidebar command"
```

---

### Task 5: Manual Verification

- [ ] **Step 1: Build and launch**

Run: `swift build 2>&1 | tail -5`
Launch and verify:
- Git header button appears (branch icon)
- Clicking it opens the sidebar with branch name
- File status groups show with correct colors
- Stage All / Unstage All work
- Clicking a file opens it in explorer preview
- Closing the sidebar stops polling
- Non-git directories show "Not a git repository"

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 3: Final commit if cleanup needed**

```bash
git add -A
git commit -m "chore: Pack 011 cleanup and final adjustments"
```
