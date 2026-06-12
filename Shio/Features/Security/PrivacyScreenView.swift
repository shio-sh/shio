import SwiftUI

/// Generic splash shown over Shio's UI when the app resigns active
/// (background, app switcher, control center). Prevents the live terminal
/// from being captured in the iOS app-switcher snapshot.
///
/// This is intentionally minimal — just the shio wordmark on the theme
/// canvas. No info leakage about which Mac you were on or what was on
/// screen.
struct PrivacyScreenView: View {
    var body: some View {
        ZStack {
            // Theme canvas, not hardcoded black — textPrimary is ink in light
            // mode, which rendered the wordmark invisible on black.
            ShioTheme.background
                .ignoresSafeArea()
            VStack(spacing: ShioSpace.md) {
                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 64))
                    .foregroundStyle(ShioTheme.textPrimary)
                Text("shio")
                    .font(.custom("DepartureMono-Regular", size: 24))
                    .foregroundStyle(ShioTheme.textPrimary)
            }
        }
    }
}
