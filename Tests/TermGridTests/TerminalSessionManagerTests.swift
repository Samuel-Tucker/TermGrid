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

    @Test func promoteSplitToPrimaryMovesSplitIntoPrimarySlot() {
        let manager = TerminalSessionManager()
        let cellID = UUID()
        let primary = manager.createSession(for: cellID, workingDirectory: "/tmp")
        let split = manager.createSplitSession(for: cellID, workingDirectory: "/tmp", direction: .horizontal)
        let splitID = split.sessionID

        manager.promoteSplitToPrimary(for: cellID)

        // Split session is now the primary
        #expect(manager.session(for: cellID)?.sessionID == splitID)
        // Split slot is cleared
        #expect(manager.splitSession(for: cellID) == nil)
        #expect(manager.splitDirection(for: cellID) == nil)
        // Old primary was killed
        #expect(primary.isRunning == false)
        manager.killAll()
    }

    @Test func promoteSplitNoOpWhenNoSplit() {
        let manager = TerminalSessionManager()
        let cellID = UUID()
        let primary = manager.createSession(for: cellID, workingDirectory: "/tmp")
        let primaryID = primary.sessionID

        manager.promoteSplitToPrimary(for: cellID)

        // Primary unchanged — no split to promote
        #expect(manager.session(for: cellID)?.sessionID == primaryID)
        #expect(primary.isRunning == true)
        manager.killAll()
    }
}
