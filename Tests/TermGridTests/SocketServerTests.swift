@testable import TermGrid
import Testing
import Foundation
import os

@Suite("SocketServer Tests")
struct SocketServerTests {

    private func tempSocketPath() -> String {
        "/tmp/termgrid-test-\(UUID().uuidString).sock"
    }

    @Test func createsSocketFileOnStart() async throws {
        let path = tempSocketPath()
        let server = SocketServer(socketPath: path)
        server.start { _ in }
        try await Task.sleep(for: .milliseconds(100))
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
    }

    @Test func removesSocketFileOnStop() async throws {
        let path = tempSocketPath()
        let server = SocketServer(socketPath: path)
        server.start { _ in }
        try await Task.sleep(for: .milliseconds(100))
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func removesStaleSocketOnStart() async throws {
        let path = tempSocketPath()
        FileManager.default.createFile(atPath: path, contents: nil)
        #expect(FileManager.default.fileExists(atPath: path))
        let server = SocketServer(socketPath: path)
        server.start { _ in }
        try await Task.sleep(for: .milliseconds(100))
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
    }

    @Test func receivesJSONPayload() async throws {
        let path = tempSocketPath()
        let server = SocketServer(socketPath: path)

        let expectation = OSAllocatedUnfairLock<SocketPayload?>(initialState: nil)

        server.start { payload in
            expectation.withLock { $0 = payload }
        }
        try await Task.sleep(for: .milliseconds(100))

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { cstr in
                strcpy(ptr, cstr)
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        let json = #"{"cellID":"550e8400-e29b-41d4-a716-446655440000","sessionType":"primary","agentType":"claudeCode","eventType":"complete","message":"Done"}"# + "\n"
        json.withCString { cstr in
            _ = Darwin.write(fd, cstr, strlen(cstr))
        }

        try await Task.sleep(for: .milliseconds(200))
        let received = expectation.withLock { $0 }
        #expect(received != nil)
        #expect(received?.cellID == "550e8400-e29b-41d4-a716-446655440000")
        #expect(received?.message == "Done")
        server.stop()
    }

    @Test func handlesMalformedJSONWithoutCrashing() async throws {
        let path = tempSocketPath()
        let server = SocketServer(socketPath: path)
        let received = OSAllocatedUnfairLock(initialState: false)
        server.start { _ in received.withLock { $0 = true } }
        try await Task.sleep(for: .milliseconds(100))

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { cstr in strcpy(ptr, cstr) }
        }
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let garbage = "not json at all\n"
        garbage.withCString { cstr in _ = Darwin.write(fd, cstr, strlen(cstr)) }

        try await Task.sleep(for: .milliseconds(200))
        #expect(!received.withLock { $0 })
        server.stop()
    }
}
