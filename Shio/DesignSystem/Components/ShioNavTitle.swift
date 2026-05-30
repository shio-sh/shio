import SwiftUI

extension View {
    /// Shio's on-brand navigation title: the tab name rendered in the
    /// Departure Mono wordmark face. Uses a `.principal` toolbar item so it
    /// sits in the bar as plain title text — unlike leading/trailing items,
    /// the principal slot doesn't get wrapped in a Liquid Glass capsule, so
    /// the wordmark reads as a wordmark, not a button.
    func shioNavTitle(_ title: String, size: CGFloat = 18) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(ShioFont.wordmark(size: size))
                        .foregroundStyle(ShioColor.Text.primary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
