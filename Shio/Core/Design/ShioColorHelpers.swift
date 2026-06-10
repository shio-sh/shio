import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform Color helpers, shared by the iOS and Mac targets. The
/// light/dark resolver works on **both** platforms — the previous iOS-only
/// version fell back to `light` on macOS, which is why the Mac had no real dark
/// mode. This is the foundation of the app-wide theme-aware design tokens.
extension Color {
    /// Construct from a 24-bit RGB hex literal: `Color(hex: 0xF4EEDF)`.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Dynamic color — resolves to `light` in light mode, `dark` in dark mode,
    /// following the system appearance on iOS and macOS.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }
}
