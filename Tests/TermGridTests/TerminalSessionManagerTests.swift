@testable import TermGrid
import Testing
import Foundation

@Suite("TerminalSessionManager Tests")
@MainActor
struct TerminalSessionManagerTests {

    @Test func sessionForUnknownIDReturnsNil() {
        let manager = TerminalSessionManager()
        #expect(manager.session(for: UUID()) == nil)
    }

    @Test func createSessionReturnsSession() {
        let manager = TerminalSessionManager()
        let cellID = UUID()
        let session = manager.createSession(for: cellID, workingDirectory: "/tmp")
        #expect(session.cellID == cellID)
        #expect(session.isRunning == true)
        manager.killAll()
    }

    @Test func sessionLookupAfterCreate() {
        let manager = TerminalSessionManager()
        let cellID = UUID()
        let created = manager.createSession(for: cellID, workingDirectory: "/tmp")
        let found = manager.session(for: cellID)
        #expect(found?.sessionID == created.sessionID)
        manager.killAll()
    }

    @Test func createSessionReplacesExisting() {
        let manager = TerminalSessionManager()
        let cellID = UUID()
        let first = manager.createSession(for: cellID, workingDirectory: "/tmp")
        let firstID = first.sessionID
        let second = manager.createSession(for: cellID, workingDirectory: "/tmp")
        #expect(second.sessionID != firstID)
        #expect(first.isRunning == false)
        #expect(manager.session(for: cellID)?.sessionID == second.sessionID)
        manager.killAll()
    }

    @Test func killSessionRemovesIt() {
        let manager = TerminalSessionManager()
        let cellID = UUID()
        let session = manager.createSession(for: cellID, workingDirectory: "/tmp")
        manager.killSession(for: cellID)
        #expect(manager.session(for: cellID) == nil)
        #expect(session.isRunning == false)
    }

    @Test func killAllRemovesAllSessions() {
        let manager = TerminalSessionManager()
        let id1 = UUID()
        let id2 = UUID()
        manager.createSession(for: id1, workingDirectory: "/tmp")
        manager.createSession(for: id2, workingDirectory: "/tmp")
        manager.killAll()
        #expect(manager.session(for: id1) == nil)
        #expect(manager.session(for: id2) == nil)
    }
}
