# API Locker Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a PIN-gated API key vault using macOS Keychain for secrets and JSON for metadata, with a right-side inspector panel and env var injection into all terminal sessions.

**Architecture:** `APIKeyVault` (`@MainActor @Observable`) manages Keychain CRUD, PIN verification (PBKDF2), in-memory key cache, and auto-lock timer. `APILockerMetadata` handles JSON persistence in `~/Library/Application Support/TermGrid/api-locker/`. The UI is a right-side panel toggled by a toolbar lock icon. `TerminalSession` accepts an optional environment array; `TerminalSessionManager` builds it from vault keys using SwiftTerm's `[String]?` format.

**Tech Stack:** SwiftUI, Security framework (Keychain), CryptoKit (PBKDF2/SHA256), Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-16-api-locker-design.md`

---

## Chunk 1: Data Model & Keychain Layer

### Task 1: Create APILockerMetadata model

**Files:**
- Create: `Sources/TermGrid/APILocker/APILockerMetadata.swift`
- Create: `Tests/TermGridTests/APILockerMetadataTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/TermGridTests/APILockerMetadataTests.swift`:

```swift
@testable import TermGrid
import Foundation
import Testing

@Suite("APIKeyEntry Tests")
struct APIKeyEntryTests {
    @Test func roundTrip() throws {
        let entry = APIKeyEntry(
            name: "OpenAI",
            envVarName: "OPENAI_API_KEY",
            brandColor: "#10A37F",
            docsURL: "https://platform.openai.com/docs",
            agentNotes: "GPT-4 key",
            maskedKey: "8X9Z"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(APIKeyEntry.self, from: data)
        #expect(decoded.name == "OpenAI")
        #expect(decoded.envVarName == "OPENAI_API_KEY")
        #expect(decoded.brandColor == "#10A37F")
        #expect(decoded.docsURL == "https://platform.openai.com/docs")
        #expect(decoded.agentNotes == "GPT-4 key")
        #expect(decoded.maskedKey == "8X9Z")
    }

    @Test func roundTripWithNilOptionals() throws {
        let entry = APIKeyEntry(
            name: "Custom",
            envVarName: "CUSTOM_KEY",
            brandColor: "#FF0000",
            docsURL: nil,
            agentNotes: nil,
            maskedKey: "abcd"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(APIKeyEntry.self, from: data)
        #expect(decoded.docsURL == nil)
        #expect(decoded.agentNotes == nil)
    }

    @Test func suggestEnvVarName() {
        #expect(APIKeyEntry.suggestEnvVarName(from: "OpenAI") == "OPENAI_API_KEY")
        #expect(APIKeyEntry.suggestEnvVarName(from: "My Stripe Key") == "MY_STRIPE_KEY_API_KEY")
        #expect(APIKeyEntry.suggestEnvVarName(from: "") == "_API_KEY")
    }

    @Test func suggestBrandColor() {
        #expect(APIKeyEntry.suggestBrandColor(for: "OpenAI") == "#10A37F")
        #expect(APIKeyEntry.suggestBrandColor(for: "anthropic prod") == "#D4A574")
        #expect(APIKeyEntry.suggestBrandColor(for: "Unknown Service") == nil)
    }
}

@Suite("APILockerMetadata Tests")
struct APILockerMetadataTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermGridLockerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func saveAndLoad() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        var meta = APILockerMetadata(pinHash: "abc123", pinSalt: "salt456")
        meta.entries.append(APIKeyEntry(
            name: "Test", envVarName: "TEST_KEY",
            brandColor: "#FF0000", docsURL: nil,
            agentNotes: nil, maskedKey: "1234"
        ))

        try APILockerMetadata.save(meta, to: dir)
        let loaded = try APILockerMetadata.load(from: dir)
        #expect(loaded?.pinHash == "abc123")
        #expect(loaded?.pinSalt == "salt456")
        #expect(loaded?.entries.count == 1)
        #expect(loaded?.entries.first?.name == "Test")
    }

    @Test func loadReturnsNilWhenMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loaded = try APILockerMetadata.load(from: dir)
        #expect(loaded == nil)
    }

    @Test func hasDuplicateEnvVar() {
        var meta = APILockerMetadata(pinHash: "", pinSalt: "")
        meta.entries.append(APIKeyEntry(
            name: "A", envVarName: "MY_KEY", brandColor: "#000",
            docsURL: nil, agentNotes: nil, maskedKey: "xxxx"
        ))
        #expect(meta.hasEnvVarName("MY_KEY") == true)
        #expect(meta.hasEnvVarName("OTHER_KEY") == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter APILocker 2>&1 | tail -20`
Expected: FAIL — types not found

- [ ] **Step 3: Create APILockerMetadata.swift**

Create `Sources/TermGrid/APILocker/APILockerMetadata.swift`:

```swift
import Foundation

struct APIKeyEntry: Codable, Identifiable {
    let id: UUID
    var name: String
    var envVarName: String
    var brandColor: String
    var docsURL: String?
    var agentNotes: String?
    var createdAt: Date
    var maskedKey: String

    init(id: UUID = UUID(), name: String, envVarName: String, brandColor: String,
         docsURL: String?, agentNotes: String?, maskedKey: String,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.envVarName = envVarName
        self.brandColor = brandColor
        self.docsURL = docsURL
        self.agentNotes = agentNotes
        self.maskedKey = maskedKey
        self.createdAt = createdAt
    }

    // MARK: - Helpers

    static func suggestEnvVarName(from name: String) -> String {
        let base = name
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return "\(base)_API_KEY"
    }

    private static let brandColors: [(pattern: String, color: String)] = [
        ("openai", "#10A37F"),
        ("anthropic", "#D4A574"),
        ("stripe", "#635BFF"),
        ("google", "#4285F4"),
        ("aws", "#FF9900"),
        ("azure", "#0078D4"),
        ("github", "#8B5CF6"),
        ("cloudflare", "#F6821F"),
    ]

    static func suggestBrandColor(for name: String) -> String? {
        let lower = name.lowercased()
        return brandColors.first { lower.contains($0.pattern) }?.color
    }
}

struct APILockerMetadata: Codable {
    var pinHash: String
    var pinSalt: String
    var entries: [APIKeyEntry]

    init(pinHash: String, pinSalt: String, entries: [APIKeyEntry] = []) {
        self.pinHash = pinHash
        self.pinSalt = pinSalt
        self.entries = entries
    }

    func hasEnvVarName(_ name: String) -> Bool {
        entries.contains { $0.envVarName == name }
    }

    // MARK: - Persistence

    private static let fileName = "metadata.json"

    static func save(_ metadata: APILockerMetadata, to directory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    static func load(from directory: URL) throws -> APILockerMetadata? {
        let fileURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(APILockerMetadata.self, from: data)
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("TermGrid")
            .appendingPathComponent("api-locker")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter APILocker 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/APILocker/APILockerMetadata.swift Tests/TermGridTests/APILockerMetadataTests.swift
git commit -m "feat: add APILockerMetadata model with JSON persistence and brand color helpers"
```

### Task 2: Create APIKeyVault (Keychain + PIN + auto-lock)

**Files:**
- Create: `Sources/TermGrid/APILocker/APIKeyVault.swift`
- Create: `Tests/TermGridTests/APIKeyVaultTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/TermGridTests/APIKeyVaultTests.swift`:

```swift
@testable import TermGrid
import Foundation
import Testing

@Suite("APIKeyVault Tests")
@MainActor
struct APIKeyVaultTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermGridVaultTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func initialStateIsNoVault() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir)
        #expect(vault.state == .noVault)
        #expect(vault.entries.isEmpty)
    }

    @Test func setPINCreatesVault() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir)
        let result = vault.setPIN("1234")
        #expect(result == true)
        #expect(vault.state == .locked)
    }

    @Test func unlockWithCorrectPIN() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir)
        vault.setPIN("5678")
        let unlocked = vault.unlock(pin: "5678")
        #expect(unlocked == true)
        if case .unlocked = vault.state {
            // good
        } else {
            Issue.record("Expected unlocked state")
        }
    }

    @Test func unlockWithWrongPIN() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir)
        vault.setPIN("1234")
        let unlocked = vault.unlock(pin: "9999")
        #expect(unlocked == false)
        #expect(vault.state == .locked)
    }

    @Test func lockClearsDecryptedKeys() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir)
        vault.setPIN("1234")
        vault.unlock(pin: "1234")
        vault.lock()
        #expect(vault.state == .locked)
        #expect(vault.decryptedKeys.isEmpty)
    }

    @Test func pinHashUsesPBKDF2() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir)
        vault.setPIN("1234")
        let meta = try APILockerMetadata.load(from: dir)
        // PBKDF2 hash should be a hex string, not a plain SHA-256
        #expect(meta?.pinHash.count == 64) // 32 bytes = 64 hex chars
        #expect(meta?.pinSalt.count == 32) // 16 bytes = 32 hex chars
        // Hash should NOT be plain SHA-256 of "1234"
        #expect(meta?.pinHash != "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4")
    }

    @Test func addAndRetrieveKey() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir, useKeychain: false) // use in-memory for tests
        vault.setPIN("1234")
        vault.unlock(pin: "1234")

        let success = vault.addKey(
            name: "OpenAI", key: "sk-test-1234567890abcdef",
            envVarName: "OPENAI_API_KEY", brandColor: "#10A37F",
            docsURL: nil, agentNotes: nil
        )
        #expect(success == true)
        #expect(vault.entries.count == 1)
        #expect(vault.entries.first?.name == "OpenAI")
        #expect(vault.entries.first?.maskedKey == "cdef")
        #expect(vault.decryptedKeys["OPENAI_API_KEY"] == "sk-test-1234567890abcdef")
    }

    @Test func removeKey() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir, useKeychain: false)
        vault.setPIN("1234")
        vault.unlock(pin: "1234")
        vault.addKey(name: "Test", key: "secret123", envVarName: "TEST_KEY",
                     brandColor: "#000", docsURL: nil, agentNotes: nil)
        let id = vault.entries.first!.id
        vault.removeKey(id: id)
        #expect(vault.entries.isEmpty)
        #expect(vault.decryptedKeys.isEmpty)
    }

    @Test func duplicateEnvVarNameRejected() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir, useKeychain: false)
        vault.setPIN("1234")
        vault.unlock(pin: "1234")
        vault.addKey(name: "A", key: "key1", envVarName: "MY_KEY",
                     brandColor: "#000", docsURL: nil, agentNotes: nil)
        let dup = vault.addKey(name: "B", key: "key2", envVarName: "MY_KEY",
                               brandColor: "#000", docsURL: nil, agentNotes: nil)
        #expect(dup == false)
        #expect(vault.entries.count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter APIKeyVaultTests 2>&1 | tail -20`
Expected: FAIL — `APIKeyVault` not found

- [ ] **Step 3: Create APIKeyVault.swift**

Create `Sources/TermGrid/APILocker/APIKeyVault.swift`:

```swift
import Foundation
import Observation
import CryptoKit
import Security

enum LockerState: Equatable {
    case noVault
    case locked
    case unlocked(expiresAt: Date)

    static func == (lhs: LockerState, rhs: LockerState) -> Bool {
        switch (lhs, rhs) {
        case (.noVault, .noVault), (.locked, .locked): return true
        case (.unlocked, .unlocked): return true
        default: return false
        }
    }
}

@MainActor
@Observable
final class APIKeyVault {
    private(set) var state: LockerState = .noVault
    private(set) var entries: [APIKeyEntry] = []
    private(set) var decryptedKeys: [String: String] = [:]
    var errorMessage: String?

    private let directory: URL
    private let useKeychain: Bool
    private var inMemoryKeys: [UUID: String] = [] // test-only fallback
    private var autoLockTimer: Timer?
    private static let autoLockInterval: TimeInterval = 900 // 15 minutes
    private static let keychainService = "com.termgrid.api-locker"

    init(directory: URL? = nil, useKeychain: Bool = true) {
        self.directory = directory ?? APILockerMetadata.defaultDirectory
        self.useKeychain = useKeychain
        loadMetadata()
    }

    // MARK: - PIN

    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        let salt = generateSalt()
        let hash = derivePINHash(pin: pin, salt: salt)
        let meta = APILockerMetadata(pinHash: hash, pinSalt: salt)
        do {
            try APILockerMetadata.save(meta, to: directory)
            entries = []
            state = .locked
            return true
        } catch {
            errorMessage = "Failed to create vault: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func unlock(pin: String) -> Bool {
        guard let meta = loadMetadataSync() else {
            errorMessage = "No vault found"
            return false
        }
        let hash = derivePINHash(pin: pin, salt: meta.pinSalt)
        guard hash == meta.pinHash else {
            errorMessage = "Wrong PIN"
            return false
        }
        errorMessage = nil
        entries = meta.entries

        // Decrypt all keys into memory
        decryptedKeys = [:]
        for entry in entries {
            if let key = readSecret(for: entry.id) {
                decryptedKeys[entry.envVarName] = key
            }
        }

        resetAutoLockTimer()
        return true
    }

    func lock() {
        decryptedKeys = [:]
        autoLockTimer?.invalidate()
        autoLockTimer = nil
        if state != .noVault {
            state = .locked
        }
    }

    // MARK: - Key Management

    @discardableResult
    func addKey(name: String, key: String, envVarName: String,
                brandColor: String, docsURL: String?, agentNotes: String?) -> Bool {
        guard case .unlocked = state else { return false }

        // Check duplicate env var
        guard !entries.contains(where: { $0.envVarName == envVarName }) else {
            errorMessage = "Environment variable '\(envVarName)' already exists"
            return false
        }

        let masked = String(key.suffix(4))
        let entry = APIKeyEntry(
            name: name, envVarName: envVarName, brandColor: brandColor,
            docsURL: docsURL, agentNotes: agentNotes, maskedKey: masked
        )

        // Store secret
        guard storeSecret(key, for: entry.id) else {
            errorMessage = "Failed to store key in Keychain"
            return false
        }

        entries.append(entry)
        decryptedKeys[envVarName] = key
        saveMetadata()
        resetAutoLockTimer()
        errorMessage = nil
        return true
    }

    func removeKey(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        deleteSecret(for: id)
        decryptedKeys.removeValue(forKey: entry.envVarName)
        entries.remove(at: index)
        saveMetadata()
        resetAutoLockTimer()
    }

    func copyKey(id: UUID) -> String? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        resetAutoLockTimer()
        return decryptedKeys[entry.envVarName]
    }

    func revealKey(id: UUID) -> String? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        resetAutoLockTimer()
        return decryptedKeys[entry.envVarName]
    }

    // MARK: - Auto-Lock Timer

    var timeRemaining: TimeInterval {
        guard case .unlocked(let expiresAt) = state else { return 0 }
        return max(0, expiresAt.timeIntervalSinceNow)
    }

    func resetAutoLockTimer() {
        autoLockTimer?.invalidate()
        let expiry = Date().addingTimeInterval(Self.autoLockInterval)
        state = .unlocked(expiresAt: expiry)
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: Self.autoLockInterval,
                                              repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lock()
            }
        }
    }

    // MARK: - PBKDF2

    private func generateSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func derivePINHash(pin: String, salt: String) -> String {
        let pinData = Data(pin.utf8)
        let saltData = Data(salt.utf8)
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pinData),
            salt: saltData,
            info: Data("termgrid-api-locker".utf8),
            outputByteCount: 32
        )
        return key.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    // MARK: - Keychain (or in-memory fallback for tests)

    private func storeSecret(_ secret: String, for id: UUID) -> Bool {
        guard useKeychain else {
            inMemoryKeys[id] = secret
            return true
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: id.uuidString,
            kSecValueData: Data(secret.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Update existing
            let update: [CFString: Any] = [kSecValueData: Data(secret.utf8)]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            return updateStatus == errSecSuccess
        }
        return status == errSecSuccess
    }

    private func readSecret(for id: UUID) -> String? {
        guard useKeychain else {
            return inMemoryKeys[id]
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: id.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSecret(for id: UUID) {
        guard useKeychain else {
            inMemoryKeys.removeValue(forKey: id)
            return
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Metadata Persistence

    private func loadMetadata() {
        if let meta = loadMetadataSync() {
            entries = meta.entries
            state = .locked
        } else {
            state = .noVault
        }
    }

    private func loadMetadataSync() -> APILockerMetadata? {
        try? APILockerMetadata.load(from: directory)
    }

    private func saveMetadata() {
        guard var meta = loadMetadataSync() else { return }
        meta.entries = entries
        try? APILockerMetadata.save(meta, to: directory)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/charles/repos/TermGrid && swift test --filter APIKeyVaultTests 2>&1 | tail -30`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/APILocker/APIKeyVault.swift Tests/TermGridTests/APIKeyVaultTests.swift
git commit -m "feat: add APIKeyVault with Keychain storage, PBKDF2 PIN, and auto-lock"
```

---

## Chunk 2: Terminal Environment Injection

### Task 3: Modify TerminalSession and TerminalSessionManager for env injection

**Files:**
- Modify: `Sources/TermGrid/Terminal/TerminalSession.swift`
- Modify: `Sources/TermGrid/Terminal/TerminalSessionManager.swift`

- [ ] **Step 1: Add environment parameter to TerminalSession.init**

In `Sources/TermGrid/Terminal/TerminalSession.swift`, change the initializer:

```swift
init(cellID: UUID, workingDirectory: String, environment: [String]? = nil) {
    self.cellID = cellID
    self.sessionID = UUID()
    self.terminalView = LocalProcessTerminalView(frame: .zero)

    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    terminalView.nativeBackgroundColor = Theme.terminalBackground
    terminalView.nativeForegroundColor = Theme.terminalForeground
    terminalView.caretColor = Theme.terminalCursor

    terminalView.startProcess(
        executable: shell,
        args: ["-l"],
        environment: environment,
        execName: nil,
        currentDirectory: workingDirectory
    )
}
```

- [ ] **Step 2: Add vault key reference and env builder to TerminalSessionManager**

In `Sources/TermGrid/Terminal/TerminalSessionManager.swift`:

Add a property for vault keys:
```swift
var vaultKeys: [String: String] = [:]
```

Add a private helper:
```swift
private func buildEnvironment() -> [String]? {
    guard !vaultKeys.isEmpty else { return nil }
    var env = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
    for (key, value) in vaultKeys {
        env.append("\(key)=\(value)")
    }
    return env
}
```

Update `createSession` to pass environment:
```swift
@discardableResult
func createSession(for cellID: UUID, workingDirectory: String) -> TerminalSession {
    if let existing = sessions[cellID] {
        existing.kill()
    }
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory,
                                   environment: buildEnvironment())
    sessions[cellID] = session
    return session
}
```

Update `createSplitSession` the same way:
```swift
@discardableResult
func createSplitSession(for cellID: UUID, workingDirectory: String,
                         direction: SplitDirection) -> TerminalSession {
    if let existing = splitSessions[cellID] {
        existing.kill()
    }
    let session = TerminalSession(cellID: cellID, workingDirectory: workingDirectory,
                                   environment: buildEnvironment())
    splitSessions[cellID] = session
    splitDirections[cellID] = direction
    return session
}
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/Terminal/TerminalSession.swift Sources/TermGrid/Terminal/TerminalSessionManager.swift
git commit -m "feat: inject vault API keys as env vars into terminal sessions"
```

---

## Chunk 3: UI — Locker Panel & Toolbar

### Task 4: Create APIKeyCard view

**Files:**
- Create: `Sources/TermGrid/APILocker/APIKeyCard.swift`

- [ ] **Step 1: Create APIKeyCard.swift**

```swift
import SwiftUI

struct APIKeyCard: View {
    let entry: APIKeyEntry
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    @State private var isRevealed = false
    @State private var revealedKey: String?
    @State private var showDeleteConfirm = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            // Brand color stripe
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: entry.brandColor))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                    .lineLimit(1)

                Text(isRevealed && revealedKey != nil ? revealedKey! : "••••\(entry.maskedKey)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.notesSecondary)
                    .lineLimit(1)
                    .textSelection(isRevealed ? .enabled : .disabled)

                Text(entry.envVarName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.composePlaceholder)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Spacer()

            // Actions
            HStack(spacing: 6) {
                Button {
                    onCopy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(copied ? Color(hex: "#10A37F") : Theme.headerIcon)
                }
                .buttonStyle(.borderless)
                .help("Copy key")

                Button {
                    if isRevealed {
                        isRevealed = false
                        revealedKey = nil
                    } else {
                        onReveal()
                        // Parent provides the key via callback — we don't store it here
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide key" : "Reveal key")

                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.borderless)
                .help("Delete key")
            }
            .padding(.trailing, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.cellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.cellBorder, lineWidth: 0.5)
        )
        .alert("Delete API Key?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove '\(entry.name)' from the vault? This cannot be undone.")
        }
    }

    func showRevealed(_ key: String) {
        revealedKey = key
        isRevealed = true
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -10`

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/APILocker/APIKeyCard.swift
git commit -m "feat: add APIKeyCard view with brand color stripe and actions"
```

### Task 5: Create APILockerPanel view

**Files:**
- Create: `Sources/TermGrid/APILocker/APILockerPanel.swift`

- [ ] **Step 1: Create APILockerPanel.swift**

This is the main inspector panel with locked and unlocked states. Create `Sources/TermGrid/APILocker/APILockerPanel.swift`:

```swift
import SwiftUI
import AppKit

struct APILockerPanel: View {
    @Bindable var vault: APIKeyVault

    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var showPIN = false
    @State private var isSettingPIN = false

    // Add key form
    @State private var newName = ""
    @State private var newKey = ""
    @State private var newEnvVar = ""
    @State private var newDocsURL = ""
    @State private var newColor = "#C4A574"
    @State private var newNotes = ""
    @State private var showAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            switch vault.state {
            case .noVault:
                setPINView
            case .locked:
                lockedView
            case .unlocked:
                unlockedView
            }
        }
        .frame(width: 280)
        .background(Theme.appBackground)
    }

    // MARK: - Set PIN (first time)

    @ViewBuilder
    private var setPINView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.rectangle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.accent)

            Text("API Locker")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.headerText)

            Text("Set a PIN to protect your keys")
                .font(.system(size: 12))
                .foregroundColor(Theme.headerIcon)

            pinField(text: $pin, placeholder: "Enter PIN (4-6 digits)")
            pinField(text: $confirmPin, placeholder: "Confirm PIN")

            Button("Set PIN") {
                guard pin.count >= 4, pin.count <= 6, pin == confirmPin else {
                    vault.errorMessage = pin != confirmPin ? "PINs don't match"
                        : "PIN must be 4-6 digits"
                    return
                }
                vault.setPIN(pin)
                pin = ""
                confirmPin = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(pin.count < 4 || confirmPin.isEmpty)

            if let error = vault.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Locked

    @ViewBuilder
    private var lockedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.rectangle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.accent)

            Text("API Locker")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.headerText)

            Text("Enter PIN to unlock keys")
                .font(.system(size: 12))
                .foregroundColor(Theme.headerIcon)

            pinField(text: $pin, placeholder: "Enter PIN")

            Button("Unlock") {
                let success = vault.unlock(pin: pin)
                if !success {
                    pin = ""
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(pin.count < 4)

            if let error = vault.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Unlocked

    @ViewBuilder
    private var unlockedView: some View {
        VStack(spacing: 0) {
            // Header with timer
            HStack {
                Text("API Locker")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                Spacer()
                AutoLockTimer(vault: vault)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Key list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vault.entries) { entry in
                        APIKeyCard(
                            entry: entry,
                            onCopy: {
                                if let key = vault.copyKey(id: entry.id) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(key, forType: .string)
                                }
                            },
                            onReveal: {
                                // Handled inside the card — vault provides the raw key
                            },
                            onDelete: {
                                vault.removeKey(id: entry.id)
                            }
                        )
                    }
                }
                .padding(12)

                // Add key section
                if showAddForm {
                    addKeyForm
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else {
                    Button {
                        showAddForm = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add API Key")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Lock button
            Button {
                vault.lock()
                pin = ""
            } label: {
                HStack {
                    Image(systemName: "lock.fill")
                    Text("Lock Vault")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
    }

    // MARK: - Add Key Form

    @ViewBuilder
    private var addKeyForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add API Key")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.headerText)

            TextField("Service Name", text: $newName)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.headerBackground))
                .onChange(of: newName) { _, name in
                    newEnvVar = APIKeyEntry.suggestEnvVarName(from: name)
                    if let color = APIKeyEntry.suggestBrandColor(for: name) {
                        newColor = color
                    }
                }

            SecureField("API Key", text: $newKey)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.headerBackground))

            TextField("ENV_VAR_NAME", text: $newEnvVar)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.headerBackground))

            TextField("Docs URL (optional)", text: $newDocsURL)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.headerBackground))

            TextField("Agent notes (optional)", text: $newNotes)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.headerBackground))

            // Color swatch row
            HStack(spacing: 4) {
                ForEach(["#10A37F", "#D4A574", "#635BFF", "#4285F4", "#FF9900",
                         "#0078D4", "#8B5CF6", "#F6821F"], id: \.self) { color in
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: newColor == color ? 2 : 0)
                        )
                        .onTapGesture { newColor = color }
                }
            }

            if let error = vault.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") {
                    showAddForm = false
                    clearAddForm()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundColor(Theme.headerIcon)

                Spacer()

                Button("Add Key") {
                    let success = vault.addKey(
                        name: newName, key: newKey, envVarName: newEnvVar,
                        brandColor: newColor,
                        docsURL: newDocsURL.isEmpty ? nil : newDocsURL,
                        agentNotes: newNotes.isEmpty ? nil : newNotes
                    )
                    if success {
                        showAddForm = false
                        clearAddForm()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .font(.system(size: 11))
                .disabled(newName.isEmpty || newKey.isEmpty || newEnvVar.isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.headerBackground)
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pinField(text: Binding<String>, placeholder: String) -> some View {
        Group {
            if showPIN {
                TextField(placeholder, text: text)
            } else {
                SecureField(placeholder, text: text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 14, design: .monospaced))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.headerBackground))
        .overlay(alignment: .trailing) {
            Button {
                showPIN.toggle()
            } label: {
                Image(systemName: showPIN ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.headerIcon)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 8)
        }
    }

    private func clearAddForm() {
        newName = ""
        newKey = ""
        newEnvVar = ""
        newDocsURL = ""
        newColor = "#C4A574"
        newNotes = ""
        vault.errorMessage = nil
    }
}

// MARK: - Auto-Lock Timer View

struct AutoLockTimer: View {
    let vault: APIKeyVault
    @State private var remaining: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatTime(remaining))
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(remaining < 60 ? Theme.accent : Theme.notesSecondary)
            .onReceive(timer) { _ in
                remaining = vault.timeRemaining
            }
            .onAppear {
                remaining = vault.timeRemaining
            }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -10`

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/APILocker/APILockerPanel.swift
git commit -m "feat: add APILockerPanel with locked/unlocked states, add key form, auto-lock timer"
```

### Task 6: Integrate into TermGridApp and ContentView

**Files:**
- Modify: `Sources/TermGrid/TermGridApp.swift`
- Modify: `Sources/TermGrid/Views/ContentView.swift`

- [ ] **Step 1: Add vault to TermGridApp**

In `Sources/TermGrid/TermGridApp.swift`, add vault state:

```swift
@State private var vault = APIKeyVault()
```

Pass vault to ContentView:

```swift
ContentView(store: store, sessionManager: sessionManager, vault: vault)
```

On termination, lock the vault:

```swift
.onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
    store.flush()
    vault.lock()
    sessionManager.killAll()
}
```

- [ ] **Step 2: Add locker panel and toolbar to ContentView**

In `Sources/TermGrid/Views/ContentView.swift`:

Add vault parameter and panel state:

```swift
@Bindable var vault: APIKeyVault
@State private var showAPILocker = false
```

Add toolbar item for the lock icon (inside the existing `.toolbar`):

```swift
ToolbarItem {
    Button {
        showAPILocker.toggle()
    } label: {
        Image(systemName: vault.state == .noVault || vault.state == .locked
              ? "lock.fill" : "lock.open.fill")
            .foregroundColor(vault.state == .locked || vault.state == .noVault
                             ? Theme.headerIcon : Theme.accent)
    }
    .help("API Locker")
}
```

Wrap the main content in an `HStack` with the locker panel:

```swift
HStack(spacing: 0) {
    // Existing GeometryReader content...
    existingGridContent

    if showAPILocker {
        Divider()
        APILockerPanel(vault: vault)
    }
}
```

- [ ] **Step 3: Wire vault keys to session manager**

In `ContentView`, observe vault key changes and update session manager:

```swift
.onChange(of: vault.decryptedKeys) { _, newKeys in
    sessionManager.vaultKeys = newKeys
}
.onAppear {
    sessionManager.vaultKeys = vault.decryptedKeys
}
```

- [ ] **Step 4: Build and verify**

Run: `cd /Users/charles/repos/TermGrid && swift build 2>&1 | tail -10`

- [ ] **Step 5: Commit**

```bash
git add Sources/TermGrid/TermGridApp.swift Sources/TermGrid/Views/ContentView.swift
git commit -m "feat: integrate API Locker panel into toolbar and content view"
```

---

## Chunk 4: Final Build & Verification

### Task 7: Release build, tests, and app update

- [ ] **Step 1: Run all tests**

Run: `cd /Users/charles/repos/TermGrid && swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 2: Release build**

Run: `cd /Users/charles/repos/TermGrid && swift build -c release 2>&1 | tail -10`

- [ ] **Step 3: Update app bundle**

```bash
pkill -f "TermGrid" 2>/dev/null; sleep 1
cp /Users/charles/repos/TermGrid/.build/release/TermGrid /Applications/TermGrid.app/Contents/MacOS/TermGrid
cp -R /Users/charles/repos/TermGrid/.build/release/TermGrid_TermGrid.bundle /Applications/TermGrid.app/Contents/Resources/
/Applications/TermGrid.app/Contents/MacOS/TermGrid &
```

- [ ] **Step 4: Manual verification**

1. Lock icon appears in toolbar
2. Click lock → API Locker panel slides in from right
3. First time: shows "Set PIN" with two PIN fields
4. Set a 4-digit PIN → transitions to locked state
5. Enter wrong PIN → error message
6. Enter correct PIN → unlocks, shows empty key list
7. Add a key (e.g., OpenAI, sk-test-1234, OPENAI_API_KEY) → card appears with green stripe
8. Copy button copies key to clipboard
9. Auto-lock countdown visible in header
10. Lock button → returns to locked state
11. Open a new terminal cell → run `echo $OPENAI_API_KEY` → should show the key (when unlocked)
12. Lock vault → open new terminal → `echo $OPENAI_API_KEY` → should be empty

- [ ] **Step 5: Commit remaining changes**

```bash
git add -A
git commit -m "feat: API Locker complete — PIN vault, Keychain storage, env injection"
```

### Task 8: Pack archive entry

- [ ] **Step 1: Create pack**

Create `packs/archive/006-api-locker.md` documenting the feature.

- [ ] **Step 2: Commit**

```bash
git add packs/archive/006-api-locker.md
git commit -m "docs: add API Locker pack archive entry"
```
