import SwiftUI

/// A per-project identity tint — a stable, muted color so a project is
/// recognizable at a glance everywhere its mark appears (overview, the project
/// header, the switcher). IDENTITY ONLY, never status — the loud
/// warning/info/success colors stay reserved for what an agent is doing.
/// Deterministic by name (a stable hash, NOT String.hashValue, which is
/// per-process random), so a project's color never changes between launches.
enum ProjectIdentity {
    /// Muted, palette-safe tints — low-saturation so a row of them reads as
    /// calm and characterful, not a rainbow. Each is distinct from the status
    /// colors. Light/dark pairs deepen for contrast on the bone canvas.
    private static func tint(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(light: Color(hex: light), dark: Color(hex: dark))
    }
    private static let palette: [Color] = [
        tint(0x7A6B48, 0xCDBD97),  // bone
        tint(0x2F7D7D, 0x5FB4B0),  // teal
        tint(0x6A5BB0, 0x9C8DE0),  // violet
        tint(0xA85070, 0xD68FA8),  // rose
        tint(0x566B96, 0x8FA8D6),  // slate
    ]

    static func color(for name: String) -> Color {
        var h: UInt64 = 5381
        for byte in name.utf8 { h = (h &* 33) &+ UInt64(byte) }
        return palette[Int(h % UInt64(palette.count))]
    }

    /// The mark's fill behind the letter.
    static func wash(for name: String) -> Color { color(for: name).opacity(0.14) }
}
