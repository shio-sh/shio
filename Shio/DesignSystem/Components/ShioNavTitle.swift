import SwiftUI

extension View {
    /// Shio's on-brand tab header: a left-aligned terminal-path title like
    /// `~/shio`, in the Departure Mono wordmark face. Rendered as a pinned
    /// header in the content (not a nav-bar item), so it stays left-aligned
    /// and bubble-free — iOS 26 wraps leading/trailing toolbar items in a
    /// Liquid Glass capsule, but content isn't touched. The nav bar is left to
    /// hold just the action buttons.
    func shioNavTitle(_ name: String, size: CGFloat = 26) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            // Flat dark nav bar to match the Mac's chrome — no translucent
            // system material lightening the top edge (the design system is
            // one set of ShioTheme tones across both platforms).
            .toolbarBackground(ShioTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 0) {
                    Text("~/")
                        .foregroundStyle(ShioTheme.textTertiary)
                    Text(name.lowercased())
                        .foregroundStyle(ShioTheme.textPrimary)
                    Spacer(minLength: 0)
                }
                .font(ShioFont.wordmark(size: size))
                .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
                .padding(.top, ShioSpace.xs)
                .padding(.bottom, ShioSpace.sm)
                .background(ShioTheme.background)
                .accessibilityAddTraits(.isHeader)
            }
    }
}
