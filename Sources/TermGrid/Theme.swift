import SwiftUI
import AppKit

/// Centralised colour palette — warm dark theme inspired by Kimi + Gemini advisor recommendations.
enum Theme {
    // MARK: - Foundation
    static let appBackground       = Color(hex: "#1A1A1E")
    static let cellBackground      = Color(hex: "#232328")
    static let cellBorder          = Color(hex: "#2E2E35")
    static let divider             = Color(hex: "#33333A")

    // MARK: - Header
    static let headerBackground    = Color(hex: "#1E1E22")
    static let headerText          = Color(hex: "#A09A8E")
    static let headerIcon          = Color(hex: "#7A756B")

    // MARK: - Terminal (SwiftTerm NSColors)
    static let terminalBackground  = NSColor(hex: "#1F1F24")
    static let terminalForeground  = NSColor(hex: "#D4C5B0")
    static let terminalCursor      = NSColor(hex: "#C4A574")

    // MARK: - Terminal Label Bar
    static let labelBarBackground  = Color(hex: "#25252A")
    static let labelBarText        = Color(hex: "#8B8378")
    static let labelBarTextActive  = Color(hex: "#D4C5B0")

    // MARK: - Compose Box
    static let composeBackground   = Color(hex: "#25252A")
    static let composeText         = NSColor(hex: "#75BE95")   // desaturated green
    static let composePlaceholder  = Color(hex: "#5C574F")
    static let composeChrome       = Color(hex: "#7A756B")

    // MARK: - Notes Panel
    static let notesBackground     = Color(hex: "#1E1E22")
    static let notesText           = Color(hex: "#A09A8E")
    static let notesSecondary      = Color(hex: "#7A756B")
    static let scratchPadText      = Color(hex: "#C4BEB5")  // brighter for readability

    // MARK: - Accent
    static let accent              = Color(hex: "#C4A574")
    static let accentDisabled      = Color(hex: "#5C574F")

    // MARK: - Git
    static let staged              = Color(hex: "#75BE95")
    static let error               = Color(hex: "#E06C75")

    // MARK: - Phantom Compose Overlay
    static let phantomCursorColor  = NSColor(hex: "#C4A574")  // amber block cursor
    static let phantomDivider      = Color(hex: "#C4A574")     // 1px top hairline

    // MARK: - Compose History Popup
    static let historyRowSelected  = Color(hex: "#2E2E35")     // highlighted row bg
    static let historyTimestamp    = Color(hex: "#7A756B")     // relative time text

    // MARK: - Session Ended Overlay
    static let overlayText         = Color(hex: "#A09A8E")

    // MARK: - Workspace Tabs
    static let tabActive           = Color(hex: "#252528")
    static let tabInactive         = Color(hex: "#222225")
    static let tabCloseButton      = Color(hex: "#7A756B")

    // MARK: - Panel Header Colors (desaturated for dark theme)
    static let panelColors: [PanelColor] = PanelColor.allCases

    // MARK: - Agent Badge Colors
    static let agentClaude         = Color(hex: "#D4A574")
    static let agentCodex          = Color(hex: "#75BE95")
    static let agentGemini         = Color(hex: "#4285F4")
    static let agentAider          = Color(hex: "#FF6B6B")
}

// MARK: - AgentType Display Properties

extension AgentType {
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex:      return "Codex"
        case .gemini:     return "Gemini"
        case .aider:      return "Aider"
        case .unknown:    return "Agent"
        }
    }

    var badgeColor: Color {
        switch self {
        case .claudeCode: return Theme.agentClaude
        case .codex:      return Theme.agentCodex
        case .gemini:     return Theme.agentGemini
        case .aider:      return Theme.agentAider
        case .unknown:    return Theme.headerIcon
        }
    }

    var iconName: String {
        switch self {
        case .claudeCode: return "brain"
        case .codex:      return "chevron.left.forwardslash.chevron.right"
        case .gemini:     return "sparkles"
        case .aider:      return "wrench"
        case .unknown:    return "cpu"
        }
    }
}

// MARK: - Panel Color Palette

enum PanelColor: String, CaseIterable, Identifiable {
    case rose      = "#B86A6A"
    case rust      = "#B87B5C"
    case gold      = "#B89A5C"
    case sage      = "#7A9B7A"
    case teal      = "#5A9B8F"
    case steel     = "#5C7A9B"
    case lavender  = "#9B8AB8"
    case slate     = "#6A7A8A"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) }

    /// Subtle header background tint
    var tint: Color { color.opacity(0.15) }

    /// Dot indicator color
    var dot: Color { color.opacity(0.85) }

    static func from(_ hex: String?) -> PanelColor? {
        guard let hex else { return nil }
        return allCases.first { $0.rawValue.uppercased() == hex.uppercased() }
    }
}

// MARK: - Hex Initializers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1.0
        )
    }
}
