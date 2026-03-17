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
        if case .unlocked = vault.state { } else { Issue.record("Expected unlocked state") }
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
        #expect(meta?.pinHash.count == 64)
        #expect(meta?.pinSalt.count == 32)
        #expect(meta?.pinHash != "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4")
    }

    @Test func addAndRetrieveKey() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = APIKeyVault(directory: dir, useKeychain: false)
        vault.setPIN("1234")
        vault.unlock(pin: "1234")
        let success = vault.addKey(name: "OpenAI", key: "sk-test-1234567890abcdef",
                                    envVarName: "OPENAI_API_KEY", brandColor: "#10A37F",
                                    docsURL: nil, agentNotes: nil)
        #expect(success == true)
        #expect(vault.entries.count == 1)
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
