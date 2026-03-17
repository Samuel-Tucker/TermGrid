import CryptoKit
import Foundation
import Security

enum LockerState: Equatable {
    case noVault
    case locked
    case unlocked(expiresAt: Date)

    static func == (lhs: LockerState, rhs: LockerState) -> Bool {
        switch (lhs, rhs) {
        case (.noVault, .noVault): return true
        case (.locked, .locked): return true
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
    var onKeyRemoved: ((UUID) -> Void)?

    private let directory: URL
    private let useKeychain: Bool
    private var inMemoryKeys: [UUID: String] = [:]
    private var autoLockTimer: Timer?

    private static let serviceName = "com.termgrid.api-locker"
    private static let autoLockInterval: TimeInterval = 900

    init(directory: URL? = nil, useKeychain: Bool = true) {
        self.directory = directory ?? APILockerMetadata.defaultDirectory
        self.useKeychain = useKeychain
        loadInitialState()
    }

    private func loadInitialState() {
        do {
            if let meta = try APILockerMetadata.load(from: directory) {
                entries = meta.entries
                state = .locked
            } else {
                state = .noVault
            }
        } catch {
            errorMessage = "Failed to load vault: \(error.localizedDescription)"
            state = .noVault
        }
    }

    // MARK: - PIN Management

    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        let saltBytes = generateRandomBytes(count: 16)
        let saltHex = saltBytes.map { String(format: "%02x", $0) }.joined()
        let hash = derivePINHash(pin: pin, salt: saltBytes)

        let metadata = APILockerMetadata(pinHash: hash, pinSalt: saltHex, entries: entries)
        do {
            try APILockerMetadata.save(metadata, to: directory)
            state = .locked
            return true
        } catch {
            errorMessage = "Failed to save PIN: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func unlock(pin: String) -> Bool {
        do {
            guard let meta = try APILockerMetadata.load(from: directory) else {
                errorMessage = "No vault found"
                return false
            }

            let saltBytes = hexToBytes(meta.pinSalt)
            let hash = derivePINHash(pin: pin, salt: saltBytes)

            guard hash == meta.pinHash else {
                errorMessage = "Incorrect PIN"
                return false
            }

            entries = meta.entries
            decryptedKeys = [:]

            // Load all keys from storage
            for entry in entries {
                if let key = loadSecret(for: entry.id) {
                    decryptedKeys[entry.envVarName] = key
                }
            }

            let expiry = Date().addingTimeInterval(Self.autoLockInterval)
            state = .unlocked(expiresAt: expiry)
            resetAutoLockTimer()
            return true
        } catch {
            errorMessage = "Failed to unlock: \(error.localizedDescription)"
            return false
        }
    }

    func lock() {
        decryptedKeys = [:]
        autoLockTimer?.invalidate()
        autoLockTimer = nil
        state = .locked
    }

    // MARK: - Key Management

    @discardableResult
    func addKey(name: String, key: String, envVarName: String, brandColor: String,
                docsURL: String?, agentNotes: String?) -> Bool {
        guard case .unlocked = state else {
            errorMessage = "Vault must be unlocked to add keys"
            return false
        }

        // Check for duplicate env var name
        if entries.contains(where: { $0.envVarName == envVarName }) {
            errorMessage = "Environment variable '\(envVarName)' already exists"
            return false
        }

        let maskedKey = String(key.suffix(4))
        let entry = APIKeyEntry(
            name: name, envVarName: envVarName, brandColor: brandColor,
            docsURL: docsURL, agentNotes: agentNotes, maskedKey: maskedKey
        )

        // Store the secret
        guard storeSecret(key, for: entry.id) else {
            errorMessage = "Failed to store key securely"
            return false
        }

        entries.append(entry)
        decryptedKeys[envVarName] = key

        // Save metadata
        do {
            guard var meta = try APILockerMetadata.load(from: directory) else { return false }
            meta.entries = entries
            try APILockerMetadata.save(meta, to: directory)
        } catch {
            errorMessage = "Failed to save metadata: \(error.localizedDescription)"
            return false
        }

        resetAutoLockTimer()
        return true
    }

    func removeKey(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]

        deleteSecret(for: id)
        decryptedKeys.removeValue(forKey: entry.envVarName)
        entries.remove(at: index)

        // Save metadata
        do {
            guard var meta = try APILockerMetadata.load(from: directory) else { return }
            meta.entries = entries
            try APILockerMetadata.save(meta, to: directory)
        } catch {
            errorMessage = "Failed to save metadata: \(error.localizedDescription)"
        }

        onKeyRemoved?(id)
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

    var isPremium: Bool {
        guard let meta = try? APILockerMetadata.load(from: directory) else { return false }
        return meta.isPremium
    }

    var timeRemaining: TimeInterval {
        guard case .unlocked(let expiresAt) = state else { return 0 }
        return max(0, expiresAt.timeIntervalSinceNow)
    }

    // MARK: - Auto-lock Timer

    func resetAutoLockTimer() {
        autoLockTimer?.invalidate()
        let expiry = Date().addingTimeInterval(Self.autoLockInterval)
        state = .unlocked(expiresAt: expiry)
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: Self.autoLockInterval, repeats: false) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lock()
            }
        }
    }

    // MARK: - PIN Hashing (HKDF<SHA256>)

    private func derivePINHash(pin: String, salt: [UInt8]) -> String {
        let pinData = Data(pin.utf8)
        let inputKey = SymmetricKey(data: pinData)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("com.termgrid.api-locker.pin".utf8),
            outputByteCount: 32
        )
        return derivedKey.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    private func generateRandomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes
    }

    private func hexToBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return bytes
    }

    // MARK: - Secret Storage

    private func storeSecret(_ secret: String, for id: UUID) -> Bool {
        if useKeychain {
            return keychainStore(secret, for: id)
        } else {
            inMemoryKeys[id] = secret
            return true
        }
    }

    private func loadSecret(for id: UUID) -> String? {
        if useKeychain {
            return keychainLoad(for: id)
        } else {
            return inMemoryKeys[id]
        }
    }

    private func deleteSecret(for id: UUID) {
        if useKeychain {
            keychainDelete(for: id)
        } else {
            inMemoryKeys.removeValue(forKey: id)
        }
    }

    // MARK: - Keychain Helpers

    private func keychainStore(_ secret: String, for id: UUID) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func keychainLoad(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
