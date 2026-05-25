import SwiftUI
import UIKit

/// Resolves Shio's design tokens into the xterm.js CSS variable set.
/// `light` and `dark` are baked from the design system — this is the single
/// place that translates token → terminal CSS.
struct TerminalTheme {
    let background: String
    let foreground: String
    let cursor:     String
    let selection:  String
    /// ANSI 0–15 as CSS hex strings.
    let ansi: [String]

    static let dark  = TerminalTheme(scheme: .dark)
    static let light = TerminalTheme(scheme: .light)

    init(scheme: UIUserInterfaceStyle) {
        switch scheme {
        case .light:
            background = "#FFFFFF"
            foreground = "#000000"
            cursor     = "#000000"
            selection  = "rgba(0,0,0,0.20)"
        default:
            background = "#000000"
            foreground = "#FFFFFF"
            cursor     = "#FFFFFF"
            selection  = "rgba(255,255,255,0.20)"
        }
        // ANSI palette is identical light/dark — macOS Terminal Basic profile.
        ansi = [
            "#000000", "#C91B00", "#00C200", "#C7C400",
            "#0225C7", "#CA30C7", "#00C5C7", "#C7C7C7",
            "#686868", "#FF6E67", "#5FFA68", "#FFFA72",
            "#6871FF", "#FF77FF", "#60FDFF", "#FFFFFF",
        ]
    }

    /// Build a JS snippet that updates `:root` CSS variables.
    func cssVariableAssignmentJS() -> String {
        var pairs: [(String, String)] = [
            ("--bg", background),
            ("--fg", foreground),
            ("--cursor", cursor),
            ("--selection", selection),
        ]
        for (i, hex) in ansi.enumerated() {
            pairs.append(("--ansi-\(i)", hex))
        }
        let assignments = pairs
            .map { "document.documentElement.style.setProperty('\($0.0)', '\($0.1)');" }
            .joined()
        return assignments
    }
}
