import SwiftUI

/// Shio's app-wide, theme-aware design-language tokens — the "terminal-refined"
/// kit on the real shio.sh palette, shared by iOS and Mac. Light is the bone
/// canvas (`#F4EEDF`) with white surfaces and ink text; dark is ink-800 with
/// ink-700 surfaces. The salt accent **flips**: ink-on-bone in light,
/// cream-on-ink in dark (like shio.sh's keycap). Status colors are deepened in
/// light for contrast on the warm canvas.
///
/// New surfaces (the command-center rail/dashboard, Machines/Files/Settings as
/// they're rebuilt) use `ShioTheme.*`; the old iOS `ShioColor` is retired as
/// each surface migrates.
enum ShioTheme {

    // MARK: raw palette (shio.sh)
    private static let ink800       = Color(hex: 0x0E0E10)
    private static let ink700       = Color(hex: 0x1C1C1E)
    private static let ink100       = Color(hex: 0xF2F2F4)
    private static let ink500       = Color(hex: 0x636368)
    private static let ink400       = Color(hex: 0x8E8E93)
    private static let bone         = Color(hex: 0xE8DCC4)
    private static let boneDiluted  = Color(hex: 0xF4EEDF)
    /// Warm brown used for hairlines/hover on the light bone canvas.
    private static let warm         = Color(red: 60/255, green: 50/255, blue: 30/255)

    // MARK: surfaces
    static let background = Color(light: boneDiluted,        dark: ink800)
    static let surface    = Color(light: .white,            dark: ink700)
    static let rail       = Color(light: Color(hex: 0xFBF6EA), dark: Color(hex: 0x0A0A0C))

    // MARK: text
    static let textPrimary   = Color(light: ink800,            dark: ink100)
    static let textSecondary = Color(light: ink500,            dark: ink400)
    static let textTertiary  = Color(light: Color(hex: 0xA39A86), dark: ink500)

    // MARK: accent (flips ink ↔ salt)
    static let accent   = Color(light: ink800,            dark: bone)
    static let accentBg = Color(light: ink800.opacity(0.07), dark: bone.opacity(0.10))

    // MARK: lines / hover
    static let line  = Color(light: warm.opacity(0.10),  dark: Color.white.opacity(0.06))
    static let line2 = Color(light: warm.opacity(0.16),  dark: Color.white.opacity(0.10))
    static let hover = Color(light: warm.opacity(0.045), dark: Color.white.opacity(0.04))

    // MARK: status (deepened in light)
    static let success = Color(light: Color(hex: 0x1F9A4E), dark: Color(hex: 0x3FB868))
    static let warning = Color(light: Color(hex: 0xB9741A), dark: Color(hex: 0xE0913A))
    static let info    = Color(light: Color(hex: 0x3A66C8), dark: Color(hex: 0x5B8DEF))
    static let danger  = Color(light: Color(hex: 0xC0413A), dark: Color(hex: 0xE0584F))

    static let successBg = Color(light: Color(hex: 0x1F9A4E).opacity(0.12), dark: Color(hex: 0x3FB868).opacity(0.10))
    static let warningBg = Color(light: Color(hex: 0xB9741A).opacity(0.12), dark: Color(hex: 0xE0913A).opacity(0.12))
    static let dangerBg  = Color(light: Color(hex: 0xC0413A).opacity(0.10), dark: Color(hex: 0xE0584F).opacity(0.10))
}
