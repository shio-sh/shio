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
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 0) {
                    Text("~/")
                        .foregroundStyle(ShioColor.Text.tertiary)
                    Text(name.lowercased())
                        .foregroundStyle(ShioColor.Text.primary)
                    Spacer(minLength: 0)
                }
                .font(ShioFont.wordmark(size: size))
                .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
                .padding(.top, ShioSpace.xs)
                .padding(.bottom, ShioSpace.sm)
                .background(ShioColor.Chrome.background)
                .accessibilityAddTraits(.isHeader)
            }
    }
}
