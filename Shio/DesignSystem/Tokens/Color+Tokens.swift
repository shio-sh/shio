import SwiftUI

/// Shio color tokens — mirrors `docs/design-tokens.md`.
/// Never use raw hex in feature code. Always reference these tokens.
enum ShioColor {

    // MARK: - Palette (raw)

    /// Cool near-black scale.
    enum Ink {
        static let _50  = Color(hex: 0xFAFAFA)
        static let _100 = Color(hex: 0xF2F2F4)
        static let _200 = Color(hex: 0xE5E5E9)
        static let _300 = Color(hex: 0xC9C9CF)
        static let _400 = Color(hex: 0x8E8E93)
        static let _500 = Color(hex: 0x636368)
        static let _600 = Color(hex: 0x3A3A3C)
        static let _700 = Color(hex: 0x1C1C1E)
        static let _800 = Color(hex: 0x0E0E10)
        static let _900 = Color(hex: 0x000000)
    }

    /// Brand identity — used sparingly.
    enum Salt {
        /// Full bone — icon, hero/marketing, identity moments only.
        static let bone        = Color(hex: 0xE8DCC4)
        /// Diluted bone — light-mode app background. ~30% toward white.
        static let boneDiluted = Color(hex: 0xF4EEDF)
    }

    /// State semantics.
    enum State {
        static let success = Color(hex: 0x30C46D)
        static let warning = Color(hex: 0xE89D3C)
        static let danger  = Color(hex: 0xE25555)
        static let info    = Color(hex: 0x5B8DEF)
    }

    // MARK: - Semantic tokens

    /// App chrome — light/dark resolved automatically.
    enum Chrome {
        /// Top-level app surface: bone-tinted in light, ink.800 in dark.
        static let background = Color(
            light: Salt.boneDiluted,
            dark:  Ink._800
        )
        /// Cards, sheets, list rows: pure white in light, ink.700 in dark.
        static let surface = Color(
            light: .white,
            dark:  Ink._700
        )
        /// Modal sheets, popovers: white in light (with shadow), ink.600 in dark.
        static let surfaceElevated = Color(
            light: .white,
            dark:  Ink._600
        )
        /// Hairlines, separators.
        static let divider = Color(
            light: Ink._200,
            dark:  Color(hex: 0x2A2A2C)
        )
        /// Field/button borders.
        static let border = Color(
            light: Ink._300,
            dark:  Ink._600
        )
        /// Filled secondary surfaces.
        static let fill = Color(
            light: Ink._100,
            dark:  Color(hex: 0x222224)
        )
        /// Pressed state on fills.
        static let fillPressed = Color(
            light: Ink._200,
            dark:  Color(hex: 0x2A2A2C)
        )
    }

    enum Text {
        static let primary = Color(
            light: Ink._900,
            dark:  Color(hex: 0xF2F2F4)
        )
        static let secondary = Color(
            light: Ink._500,
            dark:  Ink._400
        )
        static let tertiary = Color(
            light: Ink._400,
            dark:  Ink._500
        )
        static let disabled = primary.opacity(ShioOpacity.disabled)
        static let danger = Color(
            light: Color(hex: 0xCC4545),
            dark:  State.danger
        )
    }

    /// Terminal palette — macOS Terminal "Basic" profile, untouched.
    /// Do not deviate. See `docs/design-tokens.md` §1.2.
    enum Terminal {
        static let background = Color(light: .white, dark: .black)
        static let foreground = Color(light: .black, dark: .white)
        static let cursor     = foreground
        static let selection  = Color(light: .black, dark: .white).opacity(0.2)

        // ANSI palette — identical light/dark per macOS Terminal Basic.
        static let ansiBlack         = Color(hex: 0x000000)
        static let ansiRed           = Color(hex: 0xC91B00)
        static let ansiGreen         = Color(hex: 0x00C200)
        static let ansiYellow        = Color(hex: 0xC7C400)
        static let ansiBlue          = Color(hex: 0x0225C7)
        static let ansiMagenta       = Color(hex: 0xCA30C7)
        static let ansiCyan          = Color(hex: 0x00C5C7)
        static let ansiWhite         = Color(hex: 0xC7C7C7)
        static let ansiBrightBlack   = Color(hex: 0x686868)
        static let ansiBrightRed     = Color(hex: 0xFF6E67)
        static let ansiBrightGreen   = Color(hex: 0x5FFA68)
        static let ansiBrightYellow  = Color(hex: 0xFFFA72)
        static let ansiBrightBlue    = Color(hex: 0x6871FF)
        static let ansiBrightMagenta = Color(hex: 0xFF77FF)
        static let ansiBrightCyan    = Color(hex: 0x60FDFF)
        static let ansiBrightWhite   = Color(hex: 0xFFFFFF)
    }
}

/// Opacity tokens.
enum ShioOpacity {
    static let disabled: Double = 0.40
    static let muted:    Double = 0.60
    static let divider:  Double = 0.08
    static let overlay:  Double = 0.45
    static let hover:    Double = 0.06
    static let pressed:  Double = 0.12
}

// MARK: - Color helpers

extension Color {
    /// Construct from a 24-bit RGB hex literal: `Color(hex: 0xF4EEDF)`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Dynamic color — resolves to `light` in light mode, `dark` in dark mode.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #else
        self = light
        #endif
    }
}
