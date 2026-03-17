@testable import TermGrid
import Foundation
import Testing

@Suite("APIKeyEntry Tests")
struct APIKeyEntryTests {
    @Test func roundTrip() throws {
        let entry = APIKeyEntry(
            name: "OpenAI", envVarName: "OPENAI_API_KEY", brandColor: "#10A37F",
            docsURL: "https://platform.openai.com/docs", agentNotes: "GPT-4 key", maskedKey: "8X9Z"
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
            name: "Custom", envVarName: "CUSTOM_KEY", brandColor: "#FF0000",
            docsURL: nil, agentNotes: nil, maskedKey: "abcd"
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
            name: "Test", envVarName: "TEST_KEY", brandColor: "#FF0000",
            docsURL: nil, agentNotes: nil, maskedKey: "1234"
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
