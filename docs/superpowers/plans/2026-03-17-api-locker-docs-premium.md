# API Locker Docs & Premium Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a premium-gated Docs tab to the API Locker with Jina Reader integration for fetching structured API documentation, plus a toolbar hover tooltip.

**Architecture:** New `DocsManager` (`@MainActor @Observable`) handles doc CRUD and Jina API calls. `DocsTabView` provides the UI with premium gate and progressive disclosure. `APILockerMetadata` gains an `isPremium` flag with backward-compatible decoding. Storage is in `~/Library/Application Support/TermGrid/docs/` (separate from `api-locker/`).

**Tech Stack:** SwiftUI, Foundation (`URLSession`), Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-17-api-locker-docs-premium-design.md`

---

## Chunk 1: Data Model & Backward Compatibility

### Task 1: Add isPremium to APILockerMetadata

**Files:**
- Modify: `Sources/TermGrid/APILocker/APILockerMetadata.swift`
- Test: `Tests/TermGridTests/APILockerMetadataTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `Tests/TermGridTests/APILockerMetadataTests.swift`:

```swift
@Test func decodesLegacyMetadataWithoutIsPremium() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    // Write old-format JSON without isPremium
    let json = """
    {"pinHash":"abc","pinSalt":"def","entries":[]}
    """
    let fileURL = dir.appendingPathComponent("metadata.json")
    try json.data(using: .utf8)!.write(to: fileURL, options: .atomic)
    let loaded = try APILockerMetadata.load(from: dir)
    #expect(loaded?.isPremium == false)
}

@Test func isPremiumRoundTrip() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    var meta = APILockerMetadata(pinHash: "abc", pinSalt: "def")
    meta.isPremium = true
    try APILockerMetadata.save(meta, to: dir)
    let loaded = try APILockerMetadata.load(from: dir)
    #expect(loaded?.isPremium == true)
}
```

- [ ] **Step 2: Run tests — should FAIL**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter APILockerMetadata 2>&1 | tail -20`

- [ ] **Step 3: Add isPremium with custom decoder**

In `Sources/TermGrid/APILocker/APILockerMetadata.swift`, add to `APILockerMetadata`:

```swift
var isPremium: Bool
```

Update `init`:
```swift
init(pinHash: String, pinSalt: String, entries: [APIKeyEntry] = [], isPremium: Bool = false) {
    self.pinHash = pinHash
    self.pinSalt = pinSalt
    self.entries = entries
    self.isPremium = isPremium
}
```

Add custom decoder for backward compatibility:
```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pinHash = try container.decode(String.self, forKey: .pinHash)
    pinSalt = try container.decode(String.self, forKey: .pinSalt)
    entries = try container.decode([APIKeyEntry].self, forKey: .entries)
    isPremium = (try? container.decodeIfPresent(Bool.self, forKey: .isPremium)) ?? false
}
```

- [ ] **Step 4: Run tests — should PASS**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter APILockerMetadata 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/APILocker/APILockerMetadata.swift Tests/TermGridTests/APILockerMetadataTests.swift
git commit -m "feat: add isPremium flag to APILockerMetadata with backward-compatible decoding"
```

### Task 2: Create DocsManager with DocEntry model and persistence

**Files:**
- Create: `Sources/TermGrid/APILocker/DocsManager.swift`
- Create: `Tests/TermGridTests/DocsManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/TermGridTests/DocsManagerTests.swift`:

```swift
@testable import TermGrid
import Foundation
import Testing

@Suite("DocsManager Tests")
@MainActor
struct DocsManagerTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermGridDocsTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func addDocCreatesEntry() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let keyID = UUID()
        let entry = manager.addDoc(url: "https://api.openai.com/docs", forKey: keyID)
        #expect(entry != nil)
        #expect(entry?.sourceURL == "https://api.openai.com/docs")
        #expect(entry?.keyEntryID == keyID)
        #expect(entry?.status == .pending)
        #expect(manager.totalDocCount == 1)
    }

    @Test func addDocRejectsInvalidURL() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let entry = manager.addDoc(url: "javascript:alert(1)", forKey: UUID())
        #expect(entry == nil)
    }

    @Test func addDocRejectsFileURL() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let entry = manager.addDoc(url: "file:///etc/passwd", forKey: UUID())
        #expect(entry == nil)
    }

    @Test func addDocEnforces10Limit() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let keyID = UUID()
        for i in 0..<10 {
            let e = manager.addDoc(url: "https://example.com/doc\(i)", forKey: keyID)
            #expect(e != nil)
        }
        let eleventh = manager.addDoc(url: "https://example.com/doc10", forKey: keyID)
        #expect(eleventh == nil)
        #expect(manager.docsForKey(keyID).count == 10)
    }

    @Test func removeDocDeletesEntryAndFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let keyID = UUID()
        let entry = manager.addDoc(url: "https://example.com", forKey: keyID)!
        // Write a fake markdown file
        let filePath = dir.appendingPathComponent("\(entry.id.uuidString).md")
        try "# Test".write(to: filePath, atomically: true, encoding: .utf8)

        manager.removeDoc(entry)
        #expect(manager.totalDocCount == 0)
        #expect(!FileManager.default.fileExists(atPath: filePath.path))
    }

    @Test func removeDocsForKeyCascadeDeletes() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let keyID = UUID()
        _ = manager.addDoc(url: "https://example.com/a", forKey: keyID)
        _ = manager.addDoc(url: "https://example.com/b", forKey: keyID)
        #expect(manager.docsForKey(keyID).count == 2)
        manager.removeDocsForKey(keyID)
        #expect(manager.docsForKey(keyID).count == 0)
    }

    @Test func docsForKeyFiltersCorrectly() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let key1 = UUID(), key2 = UUID()
        _ = manager.addDoc(url: "https://example.com/a", forKey: key1)
        _ = manager.addDoc(url: "https://example.com/b", forKey: key2)
        #expect(manager.docsForKey(key1).count == 1)
        #expect(manager.docsForKey(key2).count == 1)
    }

    @Test func persistenceRoundTrip() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager1 = DocsManager(directory: dir)
        let keyID = UUID()
        _ = manager1.addDoc(url: "https://example.com/doc", forKey: keyID)

        // Load fresh manager from same directory
        let manager2 = DocsManager(directory: dir)
        #expect(manager2.totalDocCount == 1)
        #expect(manager2.docsForKey(keyID).first?.sourceURL == "https://example.com/doc")
    }

    @Test func loadContentReturnsNilWhenNoFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let entry = manager.addDoc(url: "https://example.com", forKey: UUID())!
        #expect(manager.loadContent(for: entry) == nil)
    }

    @Test func loadContentReturnsFileContents() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let manager = DocsManager(directory: dir)
        let entry = manager.addDoc(url: "https://example.com", forKey: UUID())!
        let filePath = dir.appendingPathComponent("\(entry.id.uuidString).md")
        try "# Hello World".write(to: filePath, atomically: true, encoding: .utf8)
        let content = manager.loadContent(for: entry)
        #expect(content == "# Hello World")
    }

    @Test func titleExtractionFromMarkdown() {
        #expect(DocsManager.extractTitle(from: "# My API Docs\nSome content") == "My API Docs")
        #expect(DocsManager.extractTitle(from: "No heading here") == nil)
        #expect(DocsManager.extractTitle(from: "## Secondary Heading\nContent") == "Secondary Heading")
    }

    @Test func urlValidation() {
        #expect(DocsManager.isValidDocURL("https://api.openai.com/docs") == true)
        #expect(DocsManager.isValidDocURL("http://example.com") == true)
        #expect(DocsManager.isValidDocURL("file:///etc/passwd") == false)
        #expect(DocsManager.isValidDocURL("javascript:alert(1)") == false)
        #expect(DocsManager.isValidDocURL("not a url") == false)
        #expect(DocsManager.isValidDocURL("") == false)
    }
}
```

- [ ] **Step 2: Run tests — should FAIL**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter DocsManagerTests 2>&1 | tail -20`

- [ ] **Step 3: Implement DocsManager**

Create `Sources/TermGrid/APILocker/DocsManager.swift`:

```swift
import Foundation
import Observation

enum DocStatus: String, Codable {
    case pending
    case fetched
    case error
}

struct DocEntry: Codable, Identifiable {
    let id: UUID
    let keyEntryID: UUID
    var sourceURL: String
    var title: String
    var fetchedAt: Date?
    var status: DocStatus
    var errorMessage: String?

    var fileName: String { "\(id.uuidString).md" }

    init(id: UUID = UUID(), keyEntryID: UUID, sourceURL: String,
         title: String = "", status: DocStatus = .pending) {
        self.id = id
        self.keyEntryID = keyEntryID
        self.sourceURL = sourceURL
        self.title = title
        self.status = status
    }
}

struct DocsIndex: Codable {
    var schemaVersion: Int = 1
    var entries: [DocEntry]

    init(entries: [DocEntry] = []) {
        self.entries = entries
    }

    private static let fileName = "docs-index.json"

    static func save(_ index: DocsIndex, to directory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    static func load(from directory: URL) -> DocsIndex {
        let fileURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return DocsIndex()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(DocsIndex.self, from: data)) ?? DocsIndex()
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TermGrid").appendingPathComponent("docs")
    }
}

@MainActor
@Observable
final class DocsManager {
    private(set) var index: DocsIndex
    private let directory: URL
    var fetchingIDs: Set<UUID> = []

    init(directory: URL? = nil) {
        let dir = directory ?? DocsIndex.defaultDirectory
        self.directory = dir
        self.index = DocsIndex.load(from: dir)
    }

    var totalDocCount: Int { index.entries.count }

    func docsForKey(_ keyID: UUID) -> [DocEntry] {
        index.entries.filter { $0.keyEntryID == keyID }
    }

    func addDoc(url: String, forKey keyID: UUID) -> DocEntry? {
        guard Self.isValidDocURL(url) else { return nil }
        guard docsForKey(keyID).count < 10 else { return nil }
        let entry = DocEntry(keyEntryID: keyID, sourceURL: url)
        index.entries.append(entry)
        saveIndex()
        return entry
    }

    func removeDoc(_ entry: DocEntry) {
        index.entries.removeAll { $0.id == entry.id }
        let filePath = directory.appendingPathComponent(entry.fileName)
        try? FileManager.default.removeItem(at: filePath)
        saveIndex()
    }

    func removeDocsForKey(_ keyID: UUID) {
        let docs = docsForKey(keyID)
        for doc in docs {
            let filePath = directory.appendingPathComponent(doc.fileName)
            try? FileManager.default.removeItem(at: filePath)
        }
        index.entries.removeAll { $0.keyEntryID == keyID }
        saveIndex()
    }

    func loadContent(for entry: DocEntry) -> String? {
        let filePath = directory.appendingPathComponent(entry.fileName)
        return try? String(contentsOf: filePath, encoding: .utf8)
    }

    func fetchDoc(_ entry: DocEntry, apiKey: String) async {
        guard let idx = index.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        fetchingIDs.insert(entry.id)
        defer { fetchingIDs.remove(entry.id) }

        let encodedURL = entry.sourceURL.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.sourceURL
        guard let requestURL = URL(string: "https://r.jina.ai/\(encodedURL)") else {
            index.entries[idx].status = .error
            index.entries[idx].errorMessage = "Invalid URL"
            saveIndex()
            return
        }

        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        request.setValue("markdown", forHTTPHeaderField: "X-Return-Format")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                index.entries[idx].status = .error
                index.entries[idx].errorMessage = "Invalid or expired API key"
                saveIndex()
                return
            }

            guard httpResponse.statusCode == 200 else {
                index.entries[idx].status = .error
                index.entries[idx].errorMessage = "HTTP \(httpResponse.statusCode)"
                saveIndex()
                return
            }

            var markdown: String
            if data.count > 2_000_000 {
                markdown = String(data: data.prefix(2_000_000), encoding: .utf8) ?? ""
                markdown += "\n\n--- Content truncated (>2 MB) ---"
            } else {
                markdown = String(data: data, encoding: .utf8) ?? ""
            }

            // Save to disk
            let filePath = directory.appendingPathComponent(entry.fileName)
            try markdown.write(to: filePath, atomically: true, encoding: .utf8)

            // Update entry
            index.entries[idx].status = .fetched
            index.entries[idx].fetchedAt = Date()
            index.entries[idx].errorMessage = nil
            if let title = Self.extractTitle(from: markdown) {
                index.entries[idx].title = title
            } else {
                // Use last path component of URL as title
                index.entries[idx].title = URL(string: entry.sourceURL)?.lastPathComponent ?? entry.sourceURL
            }
            saveIndex()
        } catch {
            if let idx = index.entries.firstIndex(where: { $0.id == entry.id }) {
                index.entries[idx].status = .error
                index.entries[idx].errorMessage = error.localizedDescription
                saveIndex()
            }
        }
    }

    // MARK: - Helpers

    static func extractTitle(from markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("## ") {
                return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func isValidDocURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host != nil else {
            return false
        }
        return true
    }

    private func saveIndex() {
        try? DocsIndex.save(index, to: directory)
    }
}
```

- [ ] **Step 4: Run tests — should PASS**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter DocsManagerTests 2>&1 | tail -30`

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/APILocker/DocsManager.swift Tests/TermGridTests/DocsManagerTests.swift
git commit -m "feat: add DocsManager with doc CRUD, Jina fetch, and persistence"
```

---

## Chunk 2: UI — Tooltip, Tabs, Premium Gate, Docs Tab

### Task 3: Add hover tooltip to toolbar lock button

**Files:**
- Modify: `Sources/TermGrid/Views/ContentView.swift`

- [ ] **Step 1: Add hover state and custom tooltip to the lock button**

In `ContentView.swift`, add a `@State private var isLockerHovered = false` property.

On the existing lock `Button`, remove `.help("API Locker")` and add:

```swift
.onHover { hovering in
    withAnimation(.easeInOut(duration: 0.15)) { isLockerHovered = hovering }
}
.overlay(alignment: .bottom) {
    Text("API Locker")
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundColor(Theme.headerText)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.cellBackground)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        )
        .offset(y: isLockerHovered ? 28 : 20)
        .opacity(isLockerHovered ? 1 : 0)
}
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/Views/ContentView.swift
git commit -m "feat: add custom hover tooltip to API Locker toolbar button"
```

### Task 4: Add tabbed layout to APILockerPanel

**Files:**
- Modify: `Sources/TermGrid/APILocker/APILockerPanel.swift`

- [ ] **Step 1: Add selectedTab state and Picker**

Add to `APILockerPanel`:
```swift
@State private var selectedTab = "keys"
```

In the unlocked view body, wrap the existing key list content in a tab structure. Add a `Picker` at the top of the unlocked view:

```swift
Picker("", selection: $selectedTab) {
    Text("Keys").tag("keys")
    Text("Docs (\(docsManager.totalDocCount))").tag("docs")
}
.pickerStyle(.segmented)
.padding(.horizontal, 12)
.padding(.top, 8)
```

Then conditionally show either the existing keys content or the new docs tab:
```swift
if selectedTab == "keys" {
    // existing key list, add form, etc.
} else {
    DocsTabView(vault: vault, docsManager: docsManager)
}
```

The `APILockerPanel` needs to receive `DocsManager` as a parameter. Update its init and the call site in `ContentView`.

- [ ] **Step 2: Create DocsManager in TermGridApp and pass through**

In `TermGridApp.swift`, add:
```swift
@State private var docsManager = DocsManager()
```

Pass it to `ContentView`, which passes it to `APILockerPanel`.

- [ ] **Step 3: Build (will fail — DocsTabView doesn't exist yet, continue to Task 5)**

### Task 5: Create DocsTabView with premium gate and doc management

**Files:**
- Create: `Sources/TermGrid/APILocker/DocsTabView.swift`

- [ ] **Step 1: Create DocsTabView**

Create `Sources/TermGrid/APILocker/DocsTabView.swift`:

```swift
import SwiftUI

struct DocsTabView: View {
    let vault: APIKeyVault
    let docsManager: DocsManager

    @State private var addingDocForKey: UUID? = nil
    @State private var newDocURL = ""
    @State private var expandedDocID: UUID? = nil

    var body: some View {
        if vault.isPremium {
            premiumContent
        } else {
            premiumGate
        }
    }

    // MARK: - Premium Gate

    @ViewBuilder
    private var premiumGate: some View {
        ZStack {
            // Blurred preview mockup
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.headerBackground)
                        .frame(height: 44)
                }
            }
            .padding(12)
            .blur(radius: 4)

            // Gate overlay
            VStack(spacing: 12) {
                Image(systemName: "lock.doc")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.accent)

                Text("API Documentation")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.headerText)

                VStack(alignment: .leading, spacing: 4) {
                    gateFeature("Store up to 10 docs per API key")
                    gateFeature("Auto-fetch & structure any API reference")
                    gateFeature("View docs inline alongside your keys")
                }

                Button {
                    // Placeholder — future: open subscribe URL
                } label: {
                    Text("Unlock with Premium — £10/year")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.cellBackground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.borderless)

                Text("Coming soon")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.composePlaceholder)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.cellBackground)
                    .shadow(color: .black.opacity(0.3), radius: 12)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gateFeature(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(Theme.accent)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Theme.notesText)
        }
    }

    // MARK: - Premium Content

    @ViewBuilder
    private var premiumContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if vault.entries.isEmpty {
                    Text("Add API keys first, then attach documentation.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.composePlaceholder)
                        .padding(12)
                } else {
                    ForEach(vault.entries) { keyEntry in
                        keyDocSection(keyEntry)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Per-Key Doc Section

    @ViewBuilder
    private func keyDocSection(_ keyEntry: APIKeyEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Key header
            HStack {
                Circle()
                    .fill(Color(hex: keyEntry.brandColor))
                    .frame(width: 8, height: 8)
                Text(keyEntry.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                Spacer()
                Text("\(docsManager.docsForKey(keyEntry.id).count)/10")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.composePlaceholder)
            }

            // Doc rows
            let docs = docsManager.docsForKey(keyEntry.id)
            ForEach(docs) { doc in
                docRow(doc)
            }

            // Add button (if under limit)
            if docs.count < 10 {
                if addingDocForKey == keyEntry.id {
                    addDocField(forKey: keyEntry.id)
                } else {
                    Button {
                        addingDocForKey = keyEntry.id
                        newDocURL = ""
                    } label: {
                        Label("Add documentation", systemImage: "plus.circle")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.composePlaceholder)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.headerBackground)
        )
    }

    // MARK: - Doc Row

    @ViewBuilder
    private func docRow(_ doc: DocEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedDocID = expandedDocID == doc.id ? nil : doc.id
                }
            } label: {
                HStack(spacing: 6) {
                    // Status indicator
                    if docsManager.fetchingIDs.contains(doc.id) {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .fill(doc.status == .fetched ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(doc.title.isEmpty ? "Untitled" : doc.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.notesText)
                            .lineLimit(1)
                        Text(doc.sourceURL)
                            .font(.system(size: 9))
                            .foregroundColor(Theme.headerIcon)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button {
                        docsManager.removeDoc(doc)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.headerIcon)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            // Error message
            if doc.status == .error, let msg = doc.errorMessage {
                Text(msg)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            // Expanded inline preview
            if expandedDocID == doc.id, doc.status == .fetched {
                if let content = docsManager.loadContent(for: doc) {
                    ScrollView {
                        Text(content)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(nsColor: Theme.terminalForeground))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .background(Theme.cellBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.cellBackground.opacity(0.5))
        )
    }

    // MARK: - Add Doc Field

    @ViewBuilder
    private func addDocField(forKey keyID: UUID) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10))
                .foregroundColor(Theme.accent)
            TextField("https://api.example.com/docs", text: $newDocURL)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Theme.notesText)
                .onSubmit { submitDoc(forKey: keyID) }
                .onKeyPress(.escape) {
                    addingDocForKey = nil
                    return .handled
                }
            Button("Fetch") { submitDoc(forKey: keyID) }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.accent)
                .disabled(newDocURL.isEmpty)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.cellBackground)
        )
    }

    private func submitDoc(forKey keyID: UUID) {
        guard let entry = docsManager.addDoc(url: newDocURL, forKey: keyID) else { return }
        addingDocForKey = nil
        newDocURL = ""

        // Auto-fetch if Jina key available
        if let jinaKey = vault.decryptedKeys["JINA_API_KEY"] {
            Task {
                await docsManager.fetchDoc(entry, apiKey: jinaKey)
            }
        }
    }
}
```

- [ ] **Step 2: Add `isPremium` accessor to APIKeyVault**

In `APIKeyVault.swift`, add a computed property:
```swift
var isPremium: Bool {
    guard let meta = try? APILockerMetadata.load(from: directory) else { return false }
    return meta.isPremium
}
```

- [ ] **Step 3: Build the full project**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -10`

- [ ] **Step 4: Commit all UI changes together**

```bash
git add Sources/TermGrid/APILocker/DocsTabView.swift Sources/TermGrid/APILocker/APILockerPanel.swift Sources/TermGrid/APILocker/APIKeyVault.swift Sources/TermGrid/Views/ContentView.swift Sources/TermGrid/TermGridApp.swift
git commit -m "feat: add docs tab with premium gate, Jina fetch, and toolbar tooltip"
```

---

## Chunk 3: Integration & Wiring

### Task 6: Wire cascade delete on key removal

**Files:**
- Modify: `Sources/TermGrid/APILocker/APIKeyVault.swift`

- [ ] **Step 1: Add onKeyRemoved callback to APIKeyVault**

The vault needs to notify when a key is removed so DocsManager can cascade. Add a closure property:

```swift
var onKeyRemoved: ((UUID) -> Void)?
```

In `removeKey(id:)`, after the existing logic, call:
```swift
onKeyRemoved?(id)
```

- [ ] **Step 2: Wire the callback in TermGridApp or ContentView**

Where `vault` and `docsManager` are both accessible, set:
```swift
vault.onKeyRemoved = { keyID in
    docsManager.removeDocsForKey(keyID)
}
```

- [ ] **Step 3: Build and run tests**

Run: `cd /Users/charles/repos/TermGrid && swift build && swift test 2>&1 | tail -20`

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/APILocker/APIKeyVault.swift Sources/TermGrid/TermGridApp.swift
git commit -m "feat: cascade-delete docs when API key removed"
```

### Task 7: Final build, test, update app bundle

- [ ] **Step 1: Full build**

Run: `cd /Users/charles/repos/TermGrid && swift build -c release 2>&1 | tail -10`

- [ ] **Step 2: Run all tests**

Run: `cd /Users/charles/repos/TermGrid && swift test 2>&1 | tail -30`

- [ ] **Step 3: Update app bundle and launch**

```bash
pkill -f "TermGrid" 2>/dev/null; sleep 1
cp /Users/charles/repos/TermGrid/.build/release/TermGrid /Applications/TermGrid.app/Contents/MacOS/TermGrid
cp -R /Users/charles/repos/TermGrid/.build/release/TermGrid_TermGrid.bundle /Applications/TermGrid.app/Contents/Resources/
/Applications/TermGrid.app/Contents/MacOS/TermGrid &
```

- [ ] **Step 4: Manual verification**

1. Lock button shows "API Locker" tooltip on hover
2. Unlock vault → segmented picker shows "Keys" and "Docs" tabs
3. Docs tab shows premium gate (blurred preview + subscribe button)
4. (Dev toggle isPremium=true) Docs tab shows key sections with "Add documentation" buttons
5. Add a doc URL → fetch starts → doc row appears with status
6. Click doc row → inline preview expands
7. Delete a doc → row removed, file cleaned up
8. Delete an API key → associated docs cascade-deleted

- [ ] **Step 5: Create pack archive entry**

Create `packs/archive/006-api-locker-docs-premium.md`

- [ ] **Step 6: Commit**

```bash
git add packs/archive/006-api-locker-docs-premium.md
git commit -m "docs: add API locker docs + premium pack archive entry"
```
