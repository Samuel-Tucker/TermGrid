import SwiftUI
import AppKit

// MARK: - Shared Tooltip Panel (singleton, non-activating, mouse-transparent)

@MainActor
final class TooltipPanel {
    static let shared = TooltipPanel()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var dismissTimer: Timer?
    private var ready = false

    private init() {
        // Delay tooltip readiness to avoid crashing during initial layout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.ready = true
        }
    }

    func show(text: String, shortcut: String?, relativeTo view: NSView) {
        guard ready else { return }
        dismiss()

        let content = TooltipContent(text: text, shortcut: shortcut)
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        panel.animationBehavior = .utilityWindow

        // Position below the view, centered, 6pt gap
        let viewFrame = view.convert(view.bounds, to: nil)
        guard let window = view.window else { return }
        let screenOrigin = window.convertToScreen(viewFrame)
        let panelSize = hosting.fittingSize
        let x = screenOrigin.midX - panelSize.width / 2
        let y = screenOrigin.minY - panelSize.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        self.panel = panel
        self.hostingView = hosting

        // Defer orderFront to avoid re-entrant constraint updates (crash fix)
        DispatchQueue.main.async {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        // Auto-dismiss after 4s
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let panel else { return }
        self.panel = nil
        self.hostingView = nil
        // Defer orderOut to avoid re-entrant constraint updates (crash fix)
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.1
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
    }
}

// MARK: - Tooltip Visual Content

private struct TooltipContent: View {
    let text: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#C4A574"))

            if let shortcut, !shortcut.isEmpty {
                Text(shortcut)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(Color(hex: "#6A655D"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: "#25252A"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color(hex: "#C4A574").opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Tooltip Trigger (NSViewRepresentable — tracks hover, triggers panel)

struct TooltipTrigger: NSViewRepresentable {
    let text: String
    let shortcut: String?

    func makeNSView(context: Context) -> TooltipTrackingView {
        let view = TooltipTrackingView()
        view.text = text
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ nsView: TooltipTrackingView, context: Context) {
        nsView.text = text
        nsView.shortcut = shortcut
    }
}

final class TooltipTrackingView: NSView {
    var text: String = ""
    var shortcut: String?
    private var trackingArea: NSTrackingArea?
    private var showTimer: Timer?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                TooltipPanel.shared.show(text: self.text, shortcut: self.shortcut, relativeTo: self)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        showTimer?.invalidate()
        showTimer = nil
        Task { @MainActor in
            TooltipPanel.shared.dismiss()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Pass all clicks through
    }
}

// MARK: - View Extension

extension View {
    /// Attach a themed tooltip that appears below on hover after 750ms.
    /// Shortcuts in parentheses are automatically extracted and shown muted.
    /// e.g. .tooltip("Quick Terminal (⌘⇧F)")
    func tooltip(_ text: String) -> some View {
        let (label, shortcut) = Self.parseTooltip(text)
        return self.overlay(
            TooltipTrigger(text: label, shortcut: shortcut)
                .allowsHitTesting(false)
        )
    }

    private static func parseTooltip(_ text: String) -> (String, String?) {
        // Extract "(⌘⇧F)" style shortcuts from end of string
        guard let openParen = text.lastIndex(of: "("),
              text.hasSuffix(")") else {
            return (text, nil)
        }
        let label = String(text[text.startIndex..<openParen]).trimmingCharacters(in: .whitespaces)
        let shortcut = String(text[text.index(after: openParen)..<text.index(before: text.endIndex)])
        return (label, shortcut)
    }
}
