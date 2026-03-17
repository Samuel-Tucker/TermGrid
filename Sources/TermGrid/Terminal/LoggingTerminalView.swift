import Foundation
import SwiftTerm

/// Subclass of LocalProcessTerminalView that captures all raw PTY output bytes.
/// These bytes include ANSI escape sequences, cursor positioning, colors — everything
/// needed to perfectly replay the terminal state.
class LoggingTerminalView: LocalProcessTerminalView {
    /// Maximum bytes to retain (1 MB). Older bytes are discarded.
    static let maxLogSize = 1_000_000

    private var ptyLog: [UInt8] = []

    override func dataReceived(slice: ArraySlice<UInt8>) {
        ptyLog.append(contentsOf: slice)

        // Cap the log to prevent unbounded memory growth
        if ptyLog.count > Self.maxLogSize {
            let excess = ptyLog.count - Self.maxLogSize
            ptyLog.removeFirst(excess)
        }

        super.dataReceived(slice: slice)
    }

    /// Get the captured raw PTY output as Data for saving to disk.
    func getRawLog() -> Data {
        return Data(ptyLog)
    }

    /// Feed previously captured raw bytes into this terminal view.
    /// Call this BEFORE startProcess() to restore scrollback.
    func replayLog(_ data: Data) {
        let bytes = [UInt8](data)
        feed(byteArray: bytes[...])
    }
}
