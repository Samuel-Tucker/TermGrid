import SwiftUI
import AppKit

// MARK: - Shared Tooltip Panel (singleton, non-activating, mouse-transparent)
// RULE: NO NSHostingView inside NSPanel — causes re-entrant constraint crash (Bug #2).
// Pure AppKit only: NSTextField + frame-based layout.

@MainActor
final class TooltipPanel {
    static let shared = TooltipPanel()

    private var panel: NSPanel?
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

        // Pure AppKit content — NO NSHostingView, NO Auto Layout
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.145, green: 0.145, blue: 0.165, alpha: 1.0).cgColor // #25252A
        container.layer?.cornerRadius = 5
        container.layer?.borderColor = NSColor(red: 0.769, green: 0.647, blue: 0.455, alpha: 0.2).cgColor // #C4A574 @ 20%
        container.layer?.borderWidth = 0.5

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(red: 0.769, green: 0.647, blue: 0.455, alpha: 1.0) // #C4A574
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.sizeToFit()

        var totalWidth = label.frame.width
        var shortcutLabel: NSTextField?

        if let shortcut, !shortcut.isEmpty {
            let sc = NSTextField(labelWithString: shortcut)
            sc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            sc.textColor = NSColor(red: 0.416, green: 0.396, blue: 0.365, alpha: 1.0) // #6A655D
            sc.backgroundColor = .clear
            sc.isBezeled = false
            sc.isEditable = false
            sc.sizeToFit()
            shortcutLabel = sc
            totalWidth += 4 + sc.frame.width // 4pt spacing
        }

        let paddingH: CGFloat = 8
        let paddingV: CGFloat = 5
        let contentHeight = max(label.frame.height, shortcutLabel?.frame.height ?? 0)
        let containerSize = NSSize(width: totalWidth + paddingH * 2, height: contentHeight + paddingV * 2)
        container.frame = NSRect(origin: .zero, size: containerSize)

        // Position label
        label.frame.origin = NSPoint(x: paddingH, y: paddingV)
        container.addSubview(label)

        // Position shortcut
        if let sc = shortcutLabel {
            sc.frame.origin = NSPoint(x: paddingH + label.frame.width + 4, y: paddingV)
            container.addSubview(sc)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: containerSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.contentView = container
        panel.animationBehavior = .utilityWindow

        // Position below the view, centered, 6pt gap
        let viewFrame = view.convert(view.bounds, to: nil)
        guard let window = view.window else { return }
        let screenOrigin = window.convertToScreen(viewFrame)
        let x = screenOrigin.midX - containerSize.width / 2
        let y = screenOrigin.minY - containerSize.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        self.panel = panel

        // Defer orderFront to next run loop iteration
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
    /// Attach a themed tooltip that appears below on hover after 250ms.
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
        guard let openParen = text.lastIndex(of: "("),
              text.hasSuffix(")") else {
            return (text, nil)
        }
        let label = String(text[text.startIndex..<openParen]).trimmingCharacters(in: .whitespaces)
        let shortcut = String(text[text.index(after: openParen)..<text.index(before: text.endIndex)])
        return (label, shortcut)
    }
}
