import SwiftUI
import AppKit

// MARK: - Shared Tooltip Panel (singleton, non-activating, mouse-transparent)
// Pure AppKit implementation — no NSHostingView, no SwiftUI views, no Auto Layout.

@MainActor
final class TooltipPanel {
    static let shared = TooltipPanel()

    private var panel: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    func show(text: String, shortcut: String?, relativeTo view: NSView) {
        dismiss()

        // -- Build label text field --
        let labelField = Self.makeLabel(
            string: text,
            font: .systemFont(ofSize: 11, weight: .medium),
            color: NSColor(srgbRed: 0xC4/255.0, green: 0xA5/255.0, blue: 0x74/255.0, alpha: 1) // #C4A574
        )

        // -- Build shortcut text field (optional) --
        var shortcutField: NSTextField?
        if let shortcut, !shortcut.isEmpty {
            shortcutField = Self.makeLabel(
                string: shortcut,
                font: .systemFont(ofSize: 10, weight: .regular),
                color: NSColor(srgbRed: 0x6A/255.0, green: 0x65/255.0, blue: 0x5D/255.0, alpha: 1) // #6A655D
            )
        }

        // -- Frame math --
        let hPad: CGFloat = 8
        let vPad: CGFloat = 5
        let gap: CGFloat = 4

        let labelSize = labelField.fittingSize
        let shortcutSize = shortcutField?.fittingSize ?? .zero

        let contentW = labelSize.width + (shortcutField != nil ? gap + shortcutSize.width : 0)
        let contentH = max(labelSize.height, shortcutSize.height)

        let totalW = hPad + contentW + hPad
        let totalH = vPad + contentH + vPad

        labelField.frame = NSRect(x: hPad, y: vPad, width: labelSize.width, height: labelSize.height)
        if let sf = shortcutField {
            sf.frame = NSRect(
                x: hPad + labelSize.width + gap,
                y: vPad,
                width: shortcutSize.width,
                height: shortcutSize.height
            )
        }

        // -- Background view (draws fill + border) --
        let bgView = TooltipBackgroundView(frame: NSRect(x: 0, y: 0, width: totalW, height: totalH))
        bgView.addSubview(labelField)
        if let sf = shortcutField { bgView.addSubview(sf) }

        // -- Panel --
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: totalW, height: totalH)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.contentView = bgView
        panel.animationBehavior = .utilityWindow

        // -- Position below the triggering view, centered, 6pt gap --
        let viewFrame = view.convert(view.bounds, to: nil)
        guard let window = view.window else { return }
        let screenOrigin = window.convertToScreen(viewFrame)
        let x = screenOrigin.midX - totalW / 2
        let y = screenOrigin.minY - totalH - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        self.panel = panel

        // Fade in
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
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
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: Helpers

    private static func makeLabel(string: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = font
        field.textColor = color
        field.backgroundColor = .clear
        field.isBordered = false
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.lineBreakMode = .byClipping
        field.sizeToFit()
        return field
    }
}

// MARK: - Tooltip Background View (frame-based, draws fill + border)

private final class TooltipBackgroundView: NSView {
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 5, yRadius: 5)

        // Fill: #25252A
        NSColor(srgbRed: 0x25/255.0, green: 0x25/255.0, blue: 0x2A/255.0, alpha: 1).setFill()
        path.fill()

        // Border: #C4A574 at 20% opacity, 0.5pt
        NSColor(srgbRed: 0xC4/255.0, green: 0xA5/255.0, blue: 0x74/255.0, alpha: 0.2).setStroke()
        path.lineWidth = 0.5
        path.stroke()
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
