import SwiftUI

/// Shio typography tokens — mirrors `docs/design-tokens.md` §2.
enum ShioFont {

    // MARK: - Families

    private static let chromeFamily   = "SF Pro"
    private static let monoFamily     = "SF Mono"
    private static let displayFamily  = "SF Pro Display"
    /// Bundled custom — pixel-grid monospace, used for the `shio` wordmark
    /// and other identity moments. PostScript name resolved from the
    /// bundled DepartureMono-Regular.otf.
    static let wordmarkFamily = "DepartureMono-Regular"
    /// Bundled custom — pixel-grid Japanese, used for the 塩 character and
    /// any other CJK glyphs that appear as identity moments. PostScript
    /// name resolved from DotGothic16-Regular.ttf.
    static let kanjiFamily    = "DotGothic16-Regular"

    // MARK: - Wordmark / kanji presets

    /// The `shio` wordmark at a given point size.
    static func wordmark(size: CGFloat) -> Font {
        .custom(wordmarkFamily, size: size)
    }

    /// The 塩 kanji at a given point size.
    static func kanji(size: CGFloat) -> Font {
        .custom(kanjiFamily, size: size)
    }

    // MARK: - Chrome scale

    /// Hero / large titles (≥34pt).
    static let display = Font.system(size: 34, weight: .semibold, design: .default)
    /// Screen titles.
    static let title1 = Font.system(size: 22, weight: .semibold, design: .default)
    /// Section headers.
    static let title2 = Font.system(size: 17, weight: .semibold, design: .default)
    /// Body, list rows, settings.
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    /// Emphasis within body.
    static let bodyEmphasis = Font.system(size: 15, weight: .medium, design: .default)
    /// Subtitles, captions, hints.
    static let callout = Font.system(size: 13, weight: .regular, design: .default)
    /// Footnotes, fingerprints, legal.
    static let footnote = Font.system(size: 11, weight: .regular, design: .default)

    // MARK: - Mono scale

    enum Mono {
        /// Default terminal font size on iPhone.
        static let terminalDefault: CGFloat = 13
        /// Default on iPad.
        static let terminalIPad: CGFloat = 14
        /// Smallest (after pinch-out).
        static let terminalMin: CGFloat = 9
        /// Largest (after pinch-in).
        static let terminalMax: CGFloat = 24

        /// Inline mono in chrome (hostnames, commands).
        static let inline = Font.system(size: 13, weight: .regular, design: .monospaced)
        /// SSH fingerprints.
        static let fingerprint = Font.system(size: 11, weight: .regular, design: .monospaced)
    }
}
