import Foundation
import SwiftTerm
import AppKit

/// Subclass of LocalProcessTerminalView that captures all raw PTY output bytes.
/// These bytes include ANSI escape sequences, cursor positioning, colors — everything
/// needed to perfectly replay the terminal state.
class LoggingTerminalView: LocalProcessTerminalView {
    /// Maximum bytes to retain (1 MB). Older bytes are discarded.
    static let maxLogSize = 1_000_000

    private var ptyLog: [UInt8] = []
    var onPatternMatch: ((PatternMatch) -> Void)? = nil
    var onAgentDetected: ((AgentType) -> Void)? = nil
    private var patternMatcher = OutputPatternMatcher()
    private var agentDetector = AgentDetector()

    /// Whether the user has scrolled back from the bottom.
    /// When true, new output will NOT auto-scroll the viewport.
    private(set) var isScrollLocked: Bool = false
    private var scrollMonitor: Any? = nil

    // MARK: - Scroll Hold

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && scrollMonitor == nil {
            // Monitor scroll wheel events to detect when user scrolls back
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                // Check if the scroll event is targeted at us
                let locationInView = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(locationInView) {
                    // After SwiftTerm processes the scroll, check if we're at bottom
                    DispatchQueue.main.async { [weak self] in
                        self?.checkScrollLockAfterUserScroll()
                    }
                }
                return event
            }
        } else if window == nil, let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    private func checkScrollLockAfterUserScroll() {
        let atBottom = scrollPosition >= 0.999
        let wasLocked = isScrollLocked
        isScrollLocked = !atBottom
        if wasLocked != isScrollLocked {
            NotificationCenter.default.post(name: .terminalScrollLockChanged, object: self)
        }
    }

    /// Call when the user sends input — scrolls to bottom and unlocks.
    func resetScrollLock() {
        guard isScrollLocked else { return }
        isScrollLocked = false
        scroll(toPosition: 1.0)
        NotificationCenter.default.post(name: .terminalScrollLockChanged, object: self)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        ptyLog.append(contentsOf: slice)

        // Cap the log to prevent unbounded memory growth
        if ptyLog.count > Self.maxLogSize {
            let excess = ptyLog.count - Self.maxLogSize
            ptyLog.removeFirst(excess)
        }

        // Scan for notification patterns
        if let callback = onPatternMatch {
            let matches = patternMatcher.processChunk(Array(slice))
            for match in matches {
                callback(match)
            }
        }

        // Scan first ~20 lines for agent startup banners
        if !agentDetector.isFinished, let callback = onAgentDetected {
            if let agent = agentDetector.processChunk(slice) {
                callback(agent)
            }
        }

        // Save scroll position before feed (which auto-scrolls to bottom)
        let savedPosition = scrollPosition
        let wasLocked = isScrollLocked

        super.dataReceived(slice: slice)

        // If user was scrolled back, restore their position so they can read
        if wasLocked {
            scroll(toPosition: savedPosition)
        }

        // Update scroll lock state: check if we're at the bottom
        let atBottom = scrollPosition >= 0.999
        if isScrollLocked != !atBottom {
            isScrollLocked = !atBottom
            NotificationCenter.default.post(name: .terminalScrollLockChanged, object: self)
        }
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
