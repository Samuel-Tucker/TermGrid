# File Explorer Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a file explorer behind each terminal cell, accessible via page-flip animation, with grid/list views, file preview, and inline editing.

**Architecture:** New `FileExplorerModel` (`@MainActor @Observable`) manages directory state, search, and navigation. Three new files: `FileExplorerView.swift` (main container with grid/list, breadcrumb, search), `FilePreviewView.swift` (read-only preview + edit header), `FileEditorView.swift` (NSTextView wrapper for editing). `CellView` gains a `ZStack` with `rotation3DEffect` to flip between terminal and explorer. Data model (`Cell`) gets two new persisted fields. Folder button becomes a `Menu` dropdown.

**Tech Stack:** SwiftUI, AppKit (`NSTextView`, `NSWorkspace`, `NSOpenPanel`), FileManager, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-16-file-explorer-design.md`

---

## Chunk 1: Data Model & Persistence

### Task 1: Add ExplorerViewMode enum and Cell fields

**Files:**
- Modify: `Sources/TermGrid/Models/Workspace.swift`
- Test: `Tests/TermGridTests/WorkspaceTests.swift`

- [ ] **Step 1: Write failing tests for new Cell fields**

Add to `Tests/TermGridTests/WorkspaceTests.swift`:

```swift
@Suite("ExplorerViewMode Tests")
struct ExplorerViewModeTests {
    @Test func rawValueRoundTrip() {
        #expect(ExplorerViewMode(rawValue: "grid") == .grid)
        #expect(ExplorerViewMode(rawValue: "list") == .list)
        #expect(ExplorerViewMode(rawValue: "unknown") == nil)
    }
}
```

Add to the existing `CellCodableTests` suite:

```swift
@Test func defaultExplorerDirectoryIsEmpty() {
    let cell = Cell()
    #expect(cell.explorerDirectory == "")
    #expect(cell.explorerViewMode == .grid)
}

@Test func roundTripWithExplorerFields() throws {
    let cell = Cell(explorerDirectory: "/tmp/project", explorerViewMode: .list)
    let data = try JSONEncoder().encode(cell)
    let decoded = try JSONDecoder().decode(Cell.self, from: data)
    #expect(decoded.explorerDirectory == "/tmp/project")
    #expect(decoded.explorerViewMode == .list)
}

@Test func decodesLegacyCellWithoutExplorerFields() throws {
    let json = """
    {"id":"00000000-0000-0000-0000-000000000001","label":"test","notes":""}
    """
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(Cell.self, from: data)
    #expect(decoded.explorerDirectory == "")
    #expect(decoded.explorerViewMode == .grid)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/charles/repos/TermGrid && swift test 2>&1 | tail -20`
Expected: FAIL — `ExplorerViewMode` not found, `explorerDirectory` not a member of `Cell`

- [ ] **Step 3: Add ExplorerViewMode enum and update Cell struct**

In `Sources/TermGrid/Models/Workspace.swift`, add before `struct Cell`:

```swift
enum ExplorerViewMode: String, Codable {
    case grid
    case list
}
```

Add new stored properties to `Cell`:

```swift
var explorerDirectory: String
var explorerViewMode: ExplorerViewMode
```

Update `Cell.init(...)` to include new params with defaults:

```swift
init(id: UUID = UUID(), label: String = "", notes: String = "",
     workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
     terminalLabel: String = "", splitTerminalLabel: String = "",
     explorerDirectory: String = "", explorerViewMode: ExplorerViewMode = .grid) {
    self.id = id
    self.label = label
    self.notes = notes
    self.workingDirectory = workingDirectory
    self.terminalLabel = terminalLabel
    self.splitTerminalLabel = splitTerminalLabel
    self.explorerDirectory = explorerDirectory
    self.explorerViewMode = explorerViewMode
}
```

Update `Cell.init(from decoder:)` — add after existing `try?` lines:

```swift
explorerDirectory = (try? container.decode(String.self, forKey: .explorerDirectory)) ?? ""
explorerViewMode = (try? container.decode(ExplorerViewMode.self, forKey: .explorerViewMode)) ?? .grid
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/charles/repos/TermGrid && swift test 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Models/Workspace.swift Tests/TermGridTests/WorkspaceTests.swift
git commit -m "feat: add ExplorerViewMode enum and explorer fields to Cell"
```

### Task 2: Add WorkspaceStore mutation methods

**Files:**
- Modify: `Sources/TermGrid/Models/WorkspaceStore.swift`
- Test: `Tests/TermGridTests/WorkspaceStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add to the existing `WorkspaceStoreTests` suite in `Tests/TermGridTests/WorkspaceStoreTests.swift` (follows the established `H.makeTempDir()` + defer pattern):

```swift
@Test func updateExplorerDirectory() throws {
    let dir = try H.makeTempDir()
    defer { H.removeTempDir(dir) }
    let store = H.makeStore(directory: dir)
    let cellID = store.workspace.cells[0].id
    store.updateExplorerDirectory("/tmp/project", for: cellID)
    #expect(store.workspace.cells[0].explorerDirectory == "/tmp/project")
}

@Test func updateExplorerViewMode() throws {
    let dir = try H.makeTempDir()
    defer { H.removeTempDir(dir) }
    let store = H.makeStore(directory: dir)
    let cellID = store.workspace.cells[0].id
    store.updateExplorerViewMode(.list, for: cellID)
    #expect(store.workspace.cells[0].explorerViewMode == .list)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/charles/repos/TermGrid && swift test 2>&1 | tail -20`
Expected: FAIL — methods not found on `WorkspaceStore`

- [ ] **Step 3: Add mutation methods to WorkspaceStore**

In `Sources/TermGrid/Models/WorkspaceStore.swift`, add after `updateSplitTerminalLabel`:

```swift
func updateExplorerDirectory(_ path: String, for cellID: UUID) {
    guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
    workspace.cells[index].explorerDirectory = path
    scheduleSave()
}

func updateExplorerViewMode(_ mode: ExplorerViewMode, for cellID: UUID) {
    guard let index = workspace.cells.firstIndex(where: { $0.id == cellID }) else { return }
    workspace.cells[index].explorerViewMode = mode
    scheduleSave()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/charles/repos/TermGrid && swift test 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Models/WorkspaceStore.swift Tests/TermGridTests/WorkspaceStoreTests.swift
git commit -m "feat: add explorer directory and view mode mutation methods"
```

---

## Chunk 2: FileExplorerModel

### Task 3: Create FileExplorerModel

**Files:**
- Create: `Sources/TermGrid/Models/FileExplorerModel.swift`
- Create: `Tests/TermGridTests/FileExplorerModelTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/TermGridTests/FileExplorerModelTests.swift`:

```swift
@testable import TermGrid
import Foundation
import Testing

@Suite("FileExplorerModel Tests")
struct FileExplorerModelTests {

    /// Helper: create a temp directory with known contents
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermGridTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // Create subdirs
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("Sources"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".git"), withIntermediateDirectories: false)
        // Create files
        try "hello".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "secret".write(to: tmp.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        return tmp
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func loadsDirectoryContents() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        // Should have Sources + README.md + package.json (dotfiles hidden by default)
        #expect(model.items.count == 3)
    }

    @Test func foldersBeforeFiles() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let firstItem = model.items.first
        #expect(firstItem?.isDirectory == true)
        #expect(firstItem?.name == "Sources")
    }

    @Test func showHiddenFilesToggle() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let countWithout = model.items.count
        model.showHiddenFiles = true
        model.loadContents()
        #expect(model.items.count > countWithout)
    }

    @Test func searchFilters() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        model.searchQuery = "READ"
        #expect(model.filteredItems.count == 1)
        #expect(model.filteredItems.first?.name == "README.md")
    }

    @Test func navigateIntoSubdirectory() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        model.navigateTo(dir.appendingPathComponent("Sources").path)
        #expect(model.currentPath == dir.appendingPathComponent("Sources").path)
        #expect(model.pathComponents.last == "Sources")
    }

    @Test func navigateBack() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        model.navigateTo(dir.appendingPathComponent("Sources").path)
        model.navigateBack()
        #expect(model.currentPath == dir.path)
    }

    @Test func navigateToBreadcrumb() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.navigateTo(dir.appendingPathComponent("Sources").path)
        model.navigateTo(dir.path) // click root breadcrumb
        #expect(model.currentPath == dir.path)
    }

    @Test func effectiveDirectoryFallback() {
        let model = FileExplorerModel(rootPath: "/tmp/test")
        #expect(model.currentPath == "/tmp/test")
    }

    @Test func createNewFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let result = model.createFile(named: "new.txt")
        #expect(result == true)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.txt").path))
    }

    @Test func createNewFolder() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let result = model.createFolder(named: "NewFolder")
        #expect(result == true)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("NewFolder").path, isDirectory: &isDir)
        #expect(isDir.boolValue == true)
    }

    @Test func createDuplicateFileFails() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        model.loadContents()
        let result = model.createFile(named: "README.md")
        #expect(result == false)
    }

    @Test func createFileWithSlashFails() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        let result = model.createFile(named: "bad/name.txt")
        #expect(result == false)
    }

    @Test func readFileReturnsContent() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        let content = model.readFile(at: dir.appendingPathComponent("README.md").path)
        #expect(content == "hello")
    }

    @Test func readFileBinaryReturnsNil() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        // Write binary data with null bytes
        let binaryPath = dir.appendingPathComponent("binary.dat")
        try Data([0x00, 0x01, 0x02, 0xFF]).write(to: binaryPath)
        let model = FileExplorerModel(rootPath: dir.path)
        // readFile returns nil only for truly unreadable files; binary detection is separate
        let content = model.readFile(at: binaryPath.path)
        // Binary data won't decode as UTF-8
        #expect(content == nil)
    }

    @Test func writeFileWorks() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let model = FileExplorerModel(rootPath: dir.path)
        let path = dir.appendingPathComponent("new.txt").path
        _ = model.createFile(named: "new.txt")
        let result = model.writeFile(at: path, content: "written")
        #expect(result == true)
        let readBack = model.readFile(at: path)
        #expect(readBack == "written")
    }

    @Test func isImageFileDetectsExtensions() {
        let model = FileExplorerModel(rootPath: "/tmp")
        #expect(model.isImageFile(at: "/foo/photo.png") == true)
        #expect(model.isImageFile(at: "/foo/photo.JPG") == true)
        #expect(model.isImageFile(at: "/foo/code.swift") == false)
    }

    @Test func isBinaryFileDetectsNullBytes() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let binaryPath = dir.appendingPathComponent("binary.dat")
        try Data([0x00, 0x01, 0x02]).write(to: binaryPath)
        let model = FileExplorerModel(rootPath: dir.path)
        #expect(model.isBinaryFile(at: binaryPath.path) == true)
        #expect(model.isBinaryFile(at: dir.appendingPathComponent("README.md").path) == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter FileExplorerModelTests 2>&1 | tail -20`
Expected: FAIL — `FileExplorerModel` not found

- [ ] **Step 3: Implement FileExplorerModel**

Create `Sources/TermGrid/Models/FileExplorerModel.swift`:

```swift
import Foundation
import Observation
import AppKit

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let fileSize: Int64
    let icon: NSImage

    var isHidden: Bool { name.hasPrefix(".") }
}

@MainActor
@Observable
final class FileExplorerModel {
    var currentPath: String
    var items: [FileItem] = []
    var searchQuery: String = ""
    var showHiddenFiles: Bool = false

    private let rootPath: String
    private static let maxItems = 500
    // Icon cache is MainActor-isolated (same as this class), so no race
    private static var iconCache: [String: NSImage] = [:]

    init(rootPath: String) {
        self.rootPath = rootPath
        self.currentPath = rootPath
    }

    var filteredItems: [FileItem] {
        guard !searchQuery.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var pathComponents: [String] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        var display = currentPath
        if display.hasPrefix(homePath) {
            display = "~" + display.dropFirst(homePath.count)
        }
        return display.split(separator: "/").map(String.init)
    }

    var shortenedPath: String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if currentPath.hasPrefix(homePath) {
            return "~" + currentPath.dropFirst(homePath.count)
        }
        return currentPath
    }

    func loadContents() {
        let url = URL(fileURLWithPath: currentPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: showHiddenFiles ? [] : [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }

        var fileItems = contents.compactMap { url -> FileItem? in
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let icon = Self.cachedIcon(for: url, isDirectory: isDir)
            return FileItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: isDir,
                fileSize: size,
                icon: icon
            )
        }

        // Sort: folders first, then alphabetical
        fileItems.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        // Cap at maxItems
        if fileItems.count > Self.maxItems {
            fileItems = Array(fileItems.prefix(Self.maxItems))
        }

        items = fileItems
    }

    func navigateTo(_ path: String) {
        currentPath = path
        searchQuery = ""
        loadContents()
    }

    func navigateBack() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        if parent.count >= rootPath.count {
            navigateTo(parent)
        }
    }

    func navigateToBreadcrumbIndex(_ index: Int) {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let components: [String]
        if currentPath.hasPrefix(homePath) {
            let relative = String(currentPath.dropFirst(homePath.count))
            components = relative.split(separator: "/").map(String.init)
            let targetComponents = Array(components.prefix(index + 1))
            let targetPath = homePath + "/" + targetComponents.joined(separator: "/")
            navigateTo(targetPath)
        } else {
            let parts = currentPath.split(separator: "/").map(String.init)
            let targetPath = "/" + parts.prefix(index + 1).joined(separator: "/")
            navigateTo(targetPath)
        }
    }

    func createFile(named name: String) -> Bool {
        guard !name.contains("/"), !name.isEmpty else { return false }
        let path = (currentPath as NSString).appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: path) else { return false }
        let success = FileManager.default.createFile(atPath: path, contents: nil)
        if success { loadContents() }
        return success
    }

    func createFolder(named name: String) -> Bool {
        guard !name.contains("/"), !name.isEmpty else { return false }
        let path = (currentPath as NSString).appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: path) else { return false }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            loadContents()
            return true
        } catch {
            return false
        }
    }

    func readFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        // Check size — truncate large files
        if data.count > 1_000_000 {
            let truncated = data.prefix(1_000_000)
            let text = String(data: truncated, encoding: .utf8) ?? "Binary file — cannot preview"
            return text + "\n\n⚠️ File truncated (>1 MB). Showing first portion only."
        }
        return String(data: data, encoding: .utf8)
    }

    func writeFile(at path: String, content: String) -> Bool {
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    func isImageFile(at path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic", "svg"].contains(ext)
    }

    func isBinaryFile(at path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path)?.prefix(512) else { return true }
        // Check for null bytes in first 512 bytes
        return data.contains(0)
    }

    private static func cachedIcon(for url: URL, isDirectory: Bool) -> NSImage {
        if isDirectory {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let ext = url.pathExtension
        if let cached = iconCache[ext] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[ext] = icon
        return icon
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter FileExplorerModelTests 2>&1 | tail -30`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/Models/FileExplorerModel.swift Tests/TermGridTests/FileExplorerModelTests.swift
git commit -m "feat: add FileExplorerModel with directory listing, search, and file operations"
```

---

## Chunk 3: CellView Changes (Dropdown, Badge, Toggle, Flip)

### Task 4: Replace folder button with Menu dropdown

**Files:**
- Modify: `Sources/TermGrid/Views/CellView.swift`
- Modify: `Sources/TermGrid/Views/ContentView.swift`

- [ ] **Step 1: Add new callbacks to CellView**

Add to `CellView`'s properties:

```swift
let onUpdateExplorerDirectory: (String) -> Void
let onUpdateExplorerViewMode: (ExplorerViewMode) -> Void
```

- [ ] **Step 2: Replace the folder `headerIconButton` with a Menu**

Replace the existing folder `headerIconButton(...)` call in `headerView` with:

```swift
// Folder dropdown menu — wrapped in dock-hover container
let folderId = "folder"
let isFolderHovered = hoveredHeaderButton == folderId
let folderNeighbor = isNeighbor(folderId, to: hoveredHeaderButton)
let folderScale: CGFloat = isFolderHovered ? 1.35 : (folderNeighbor ? 1.12 : 1.0)
let folderBlur: CGFloat = isFolderHovered ? 0 : (hoveredHeaderButton != nil ? (folderNeighbor ? 0.5 : 1.5) : 0)

Menu {
    Button("Set Terminal Directory") { pickWorkingDirectory() }
    Button("Set Explorer Directory") { pickExplorerDirectory() }
} label: {
    Image(systemName: "folder")
        .font(.system(size: 12))
        .foregroundColor(isFolderHovered ? Theme.accent : Theme.headerIcon)
}
.menuStyle(.borderlessButton)
.scaleEffect(folderScale)
.blur(radius: folderBlur)
.zIndex(isFolderHovered ? 1 : 0)
.overlay(alignment: .top) {
    Text("Directory")
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
        .offset(y: isFolderHovered ? -24 : -16)
        .opacity(isFolderHovered ? 1 : 0)
}
.onHover { hovering in
    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
        hoveredHeaderButton = hovering ? folderId : nil
    }
}
.animation(.spring(response: 0.3, dampingFraction: 0.75), value: hoveredHeaderButton)
```

- [ ] **Step 3: Add `pickExplorerDirectory()` method**

```swift
private func pickExplorerDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    let effectiveDir = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
    panel.directoryURL = URL(fileURLWithPath: effectiveDir)
    panel.prompt = "Select"
    panel.message = "Choose a directory for the file explorer"

    if panel.runModal() == .OK, let url = panel.url {
        onUpdateExplorerDirectory(url.path)
    }
}
```

- [ ] **Step 4: Wire callbacks in ContentView**

In `ContentView.swift`, add the new callbacks to the `CellView(...)` initializer:

```swift
onUpdateExplorerDirectory: { newPath in
    store.updateExplorerDirectory(newPath, for: cell.id)
},
onUpdateExplorerViewMode: { mode in
    store.updateExplorerViewMode(mode, for: cell.id)
}
```

- [ ] **Step 5: Build to verify compilation**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/TermGrid/Views/CellView.swift Sources/TermGrid/Views/ContentView.swift
git commit -m "feat: replace folder button with dropdown menu for terminal/explorer directory"
```

### Task 5: Add repo pill badge

**Files:**
- Modify: `Sources/TermGrid/Views/CellView.swift`

- [ ] **Step 1: Add pill badge to header view**

In the `headerView`, after the label `Text(...)` and before `Spacer()`, add:

```swift
// Repo pill badge
if let badgePath = effectiveExplorerPath, badgePath != FileManager.default.homeDirectoryForCurrentUser.path {
    Button {
        withAnimation(.easeInOut(duration: 0.4)) { showExplorer = true }
    } label: {
        Text(shortenPath(badgePath))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Theme.cellBorder)
            )
    }
    .buttonStyle(.borderless)
}
```

- [ ] **Step 2: Add helper computed properties to CellView**

```swift
private var effectiveExplorerPath: String? {
    let path = cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory
    return path.isEmpty ? nil : path
}

private func shortenPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
```

- [ ] **Step 3: Build and test visually**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/Views/CellView.swift
git commit -m "feat: add repo pill badge to cell header"
```

### Task 6: Add explorer toggle button and page flip

**Files:**
- Modify: `Sources/TermGrid/Views/CellView.swift`

- [ ] **Step 1: Add showExplorer state and update headerButtonIDs**

```swift
@State private var showExplorer = false
```

Update:
```swift
private static let headerButtonIDs = ["splitH", "splitV", "folder", "explorer", "notes"]
```

- [ ] **Step 2: Add explorer toggle button to header**

After the folder menu and before the notes button, add:

```swift
headerIconButton(
    id: "explorer",
    systemName: showExplorer ? "terminal" : "doc.text.magnifyingglass",
    label: showExplorer ? "Show terminal" : "Show explorer",
    action: {
        withAnimation(.easeInOut(duration: 0.4)) {
            showExplorer.toggle()
        }
    }
)
```

- [ ] **Step 3: Wrap terminalBody in page flip ZStack**

Replace the current `terminalBody` reference in the body with a new `cellBody` computed property:

```swift
@ViewBuilder
private var cellBody: some View {
    ZStack {
        terminalBody
            .opacity(showExplorer ? 0 : 1)
            .rotation3DEffect(
                .degrees(showExplorer ? -90 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )

        FileExplorerView(
            rootPath: cell.explorerDirectory.isEmpty ? cell.workingDirectory : cell.explorerDirectory,
            viewMode: cell.explorerViewMode,
            onViewModeChange: onUpdateExplorerViewMode
        )
        .opacity(showExplorer ? 1 : 0)
        .rotation3DEffect(
            .degrees(showExplorer ? 0 : 90),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
    }
    .animation(.easeInOut(duration: 0.4), value: showExplorer)
}
```

In the main `body`, replace `terminalBody` with `cellBody` inside the `HStack`.

- [ ] **Step 4: Do NOT commit yet — FileExplorerView doesn't exist. Continue to Task 7.**

Note: CellView now references `FileExplorerView` which will be created in Task 7. The commit for Tasks 6+7+8 happens after all view files are created (end of Task 8).

---

## Chunk 4: File Explorer Views

### Task 7: Create FileExplorerView (main container)

**Files:**
- Create: `Sources/TermGrid/Views/FileExplorerView.swift`

- [ ] **Step 1: Create FileExplorerView**

Create `Sources/TermGrid/Views/FileExplorerView.swift`:

```swift
import SwiftUI
import AppKit

struct FileExplorerView: View {
    let rootPath: String
    let viewMode: ExplorerViewMode
    let onViewModeChange: (ExplorerViewMode) -> Void

    @State private var model: FileExplorerModel
    @State private var previewingFile: String? = nil
    @State private var isEditing = false
    @State private var showNewItemField = false
    @State private var newItemName = ""
    @State private var newItemIsFolder = false

    init(rootPath: String, viewMode: ExplorerViewMode, onViewModeChange: @escaping (ExplorerViewMode) -> Void) {
        self.rootPath = rootPath
        self.viewMode = viewMode
        self.onViewModeChange = onViewModeChange
        self._model = State(initialValue: FileExplorerModel(rootPath: rootPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let filePath = previewingFile {
                FilePreviewView(
                    filePath: filePath,
                    model: model,
                    isEditing: $isEditing,
                    onBack: { previewingFile = nil; isEditing = false }
                )
            } else {
                // Breadcrumb
                breadcrumbBar

                // Search + view toggle + new button
                toolBar

                // File grid or list
                if model.filteredItems.isEmpty {
                    emptyState
                } else {
                    fileContent
                }
            }
        }
        .background(Theme.cellBackground)
        .onAppear { model.loadContents() }
        .onChange(of: rootPath) { _, newPath in
            model.navigateTo(newPath)
        }
    }

    // MARK: - Breadcrumb

    @ViewBuilder
    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.pathComponents.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.headerIcon)
                    }
                    let isLast = index == model.pathComponents.count - 1
                    Button(component) {
                        model.navigateToBreadcrumbIndex(index)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundColor(isLast ? Theme.headerText : Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Theme.headerBackground)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolBar: some View {
        HStack(spacing: 6) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerIcon)
                TextField("Search files...", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.notesText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.headerBackground)
            )

            // Hidden files toggle
            Button {
                model.showHiddenFiles.toggle()
                model.loadContents()
            } label: {
                Image(systemName: model.showHiddenFiles ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(model.showHiddenFiles ? Theme.accent : Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .help(model.showHiddenFiles ? "Hide dotfiles" : "Show dotfiles")

            // View mode toggle
            Button {
                onViewModeChange(.grid)
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(viewMode == .grid ? Theme.accent : Theme.headerIcon)
            }
            .buttonStyle(.borderless)

            Button {
                onViewModeChange(.list)
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11))
                    .foregroundColor(viewMode == .list ? Theme.accent : Theme.headerIcon)
            }
            .buttonStyle(.borderless)

            // New file/folder
            Menu {
                Button("New File") {
                    newItemIsFolder = false
                    showNewItemField = true
                    newItemName = ""
                }
                Button("New Folder") {
                    newItemIsFolder = true
                    showNewItemField = true
                    newItemName = ""
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerIcon)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)

        // Inline new item field
        if showNewItemField {
            HStack(spacing: 6) {
                Image(systemName: newItemIsFolder ? "folder.badge.plus" : "doc.badge.plus")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accent)
                TextField(newItemIsFolder ? "Folder name..." : "File name...", text: $newItemName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.notesText)
                    .onSubmit { createNewItem() }
                    .onKeyPress(.escape) {
                        showNewItemField = false
                        return .handled
                    }
                Button("Create") { createNewItem() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.headerBackground)
        }
    }

    // MARK: - File Content

    @ViewBuilder
    private var fileContent: some View {
        ScrollView {
            if viewMode == .grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 12) {
                    ForEach(model.filteredItems) { item in
                        fileGridItem(item)
                    }
                }
                .padding(10)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.filteredItems.enumerated()), id: \.element.id) { index, item in
                        fileListRow(item, index: index)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func fileGridItem(_ item: FileItem) -> some View {
        Button {
            handleItemClick(item)
        } label: {
            VStack(spacing: 4) {
                if item.isDirectory {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.accent)
                } else {
                    Image(nsImage: item.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
                Text(item.name)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.notesText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 70)
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func fileListRow(_ item: FileItem, index: Int) -> some View {
        Button {
            handleItemClick(item)
        } label: {
            HStack(spacing: 8) {
                if item.isDirectory {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accent)
                        .frame(width: 20)
                } else {
                    Image(nsImage: item.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .frame(width: 20)
                }
                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.notesText)
                    .lineLimit(1)
                Spacer()
                if item.isDirectory {
                    // Could show item count, but that requires extra FS calls
                } else {
                    Text(formatFileSize(item.fileSize))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.headerIcon)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(index % 2 == 0 ? Theme.cellBackground : Theme.headerBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundColor(Theme.headerIcon)
            Text(model.searchQuery.isEmpty ? "Empty directory" : "No matching files")
                .font(.system(size: 12))
                .foregroundColor(Theme.composePlaceholder)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func handleItemClick(_ item: FileItem) {
        if item.isDirectory {
            model.navigateTo(item.path)
        } else {
            previewingFile = item.path
            isEditing = false
        }
    }

    private func createNewItem() {
        guard !newItemName.isEmpty else { return }
        let success: Bool
        if newItemIsFolder {
            success = model.createFolder(named: newItemName)
        } else {
            success = model.createFile(named: newItemName)
        }
        if success {
            showNewItemField = false
            newItemName = ""
        }
        // If !success, field stays visible so user can fix the name
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -10`
Expected: Build succeeds (or may need FilePreviewView — create stub next)

- [ ] **Step 3: Do NOT commit yet — continue to Task 8.**

### Task 8: Create FilePreviewView and FileEditorView

**Files:**
- Create: `Sources/TermGrid/Views/FilePreviewView.swift`
- Create: `Sources/TermGrid/Views/FileEditorView.swift`

- [ ] **Step 1: Create FilePreviewView**

Create `Sources/TermGrid/Views/FilePreviewView.swift`:

```swift
import SwiftUI
import AppKit

struct FilePreviewView: View {
    let filePath: String
    let model: FileExplorerModel
    @Binding var isEditing: Bool
    let onBack: () -> Void

    @State private var fileContent: String = ""
    @State private var editContent: String = ""
    @State private var showUnsavedAlert = false

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var isImage: Bool {
        model.isImageFile(at: filePath)
    }

    private var isBinary: Bool {
        !isImage && model.isBinaryFile(at: filePath)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider()

            // Content
            if isImage {
                imagePreview
            } else if isBinary {
                binaryMessage
            } else if isEditing {
                editorView
            } else {
                previewView
            }
        }
        .onAppear { loadFile() }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                if isEditing && editContent != fileContent {
                    showUnsavedAlert = true
                } else {
                    onBack()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.borderless)

            Text(fileName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.headerText)
                .lineLimit(1)

            Spacer()

            if !isImage && !isBinary {
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        editContent = fileContent
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.headerIcon)

                    Button("Save") {
                        if model.writeFile(at: filePath, content: editContent) {
                            fileContent = editContent
                            isEditing = false
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.accent)
                } else {
                    Button("Edit") {
                        editContent = fileContent
                        isEditing = true
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.accent)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.headerBackground)
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Discard", role: .destructive) {
                isEditing = false
                onBack()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Discard them?")
        }
    }

    // MARK: - Preview (read-only, with line numbers)

    @ViewBuilder
    private var previewView: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                // Line number gutter
                let lines = fileContent.components(separatedBy: "\n")
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                        Text("\(index + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.composePlaceholder)
                            .frame(height: 16)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .background(Theme.cellBackground)

                // File content
                Text(fileContent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(nsColor: Theme.terminalForeground))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
        }
        .background(Theme.headerBackground)
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorView: some View {
        FileEditorTextView(text: $editContent)
            .background(Theme.headerBackground)
    }

    // MARK: - Image Preview

    private var imageFileSize: Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
        return (attrs?[.size] as? Int64) ?? 0
    }

    @ViewBuilder
    private var imagePreview: some View {
        ScrollView {
            if imageFileSize > 10_000_000 {
                // Too large to preview
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.headerIcon)
                    Text(fileName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.notesText)
                    Text("Image too large to preview (\(ByteCountFormatter.string(fromByteCount: imageFileSize, countStyle: .file)))")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.composePlaceholder)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let nsImage = NSImage(contentsOfFile: filePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(10)
            } else {
                Text("Could not load image")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.composePlaceholder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.headerBackground)
    }

    // MARK: - Binary

    @ViewBuilder
    private var binaryMessage: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.questionmark")
                .font(.system(size: 32))
                .foregroundColor(Theme.headerIcon)
            Text("Binary file — cannot preview")
                .font(.system(size: 12))
                .foregroundColor(Theme.composePlaceholder)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.headerBackground)
    }

    // MARK: - Load

    private func loadFile() {
        if let content = model.readFile(at: filePath) {
            fileContent = content
        } else if !isImage {
            fileContent = "Could not read file"
        }
    }
}

// MARK: - NSTextView wrapper for editing

struct FileEditorTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = Theme.terminalForeground
        textView.backgroundColor = Theme.terminalBackground
        textView.insertionPointColor = Theme.terminalCursor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
```

- [ ] **Step 2: Extract FileEditorTextView to its own file**

Create `Sources/TermGrid/Views/FileEditorView.swift` — move the `FileEditorTextView` struct and its `Coordinator` from `FilePreviewView.swift` into this file. `FilePreviewView` imports and references it.

The `FileEditorView.swift` file contains only:
```swift
import SwiftUI
import AppKit

struct FileEditorTextView: NSViewRepresentable { ... }
```

(The full code is already written above in the `FilePreviewView` step — just extract it to a separate file.)

- [ ] **Step 3: Build the full project**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -10`
Expected: Build succeeds (all Tasks 6+7+8 files now exist)

- [ ] **Step 4: Commit all view files and CellView changes together**

```bash
git add Sources/TermGrid/Views/CellView.swift Sources/TermGrid/Views/FileExplorerView.swift Sources/TermGrid/Views/FilePreviewView.swift Sources/TermGrid/Views/FileEditorView.swift Sources/TermGrid/Views/ContentView.swift
git commit -m "feat: add file explorer with page flip, grid/list views, preview, and inline editor"
```

---

## Chunk 5: Final Integration & Testing

### Task 9: Build, run, and verify end-to-end

- [ ] **Step 1: Full build**

Run: `cd /Users/charles/repos/TermGrid && swift build -c release 2>&1 | tail -10`

- [ ] **Step 2: Run all tests**

Run: `cd /Users/charles/repos/TermGrid && swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 3: Update app bundle**

```bash
pkill -f "TermGrid" 2>/dev/null; sleep 1
cp /Users/charles/repos/TermGrid/.build/release/TermGrid /Applications/TermGrid.app/Contents/MacOS/TermGrid
cp -R /Users/charles/repos/TermGrid/.build/release/TermGrid_TermGrid.bundle /Applications/TermGrid.app/Contents/Resources/
```

- [ ] **Step 4: Manual verification checklist**

Test each of these in the running app:
1. Folder button shows dropdown with "Set Terminal Directory" and "Set Explorer Directory"
2. Setting explorer directory shows repo pill badge in header
3. Clicking pill badge flips to explorer
4. Explorer toggle button (magnifying glass icon) flips the cell
5. Page flip animation is smooth
6. Breadcrumb navigation works (click path components)
7. Grid view shows folders + files
8. List view toggle works
9. Search filters files
10. Click folder → navigates in
11. Click file → shows preview
12. Edit button → inline editor works
13. Save/Cancel work correctly
14. New file/folder creation works
15. Hidden files toggle works
16. Back button from preview returns to listing

- [ ] **Step 5: Commit all remaining changes**

```bash
git add -A
git commit -m "feat: file explorer integration complete — page flip, preview, inline edit"
```

### Task 10: Add pack archive entry

- [ ] **Step 1: Create pack**

Create `packs/archive/005-file-explorer.md` documenting the feature.

- [ ] **Step 2: Commit**

```bash
git add packs/archive/005-file-explorer.md
git commit -m "docs: add file explorer pack archive entry"
```
