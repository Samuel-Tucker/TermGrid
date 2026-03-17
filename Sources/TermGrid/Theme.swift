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

    // MARK: - Accent
    static let accent              = Color(hex: "#C4A574")
    static let accentDisabled      = Color(hex: "#5C574F")

    // MARK: - Session Ended Overlay
    static let overlayText         = Color(hex: "#A09A8E")
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
