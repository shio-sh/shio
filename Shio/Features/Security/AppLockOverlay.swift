import SwiftUI

/// Full-screen view shown over Shio's UI whenever the app is locked.
/// Owns its own biometric flow — no singleton dependency. The parent
/// (`RootView`) toggles this in/out via a `@State` Bool and supplies
/// the `onUnlocked` callback.
struct AppLockOverlay: View {

    let onUnlocked: () -> Void

    @State private var biometricError: String?
    @State private var inFlight: Bool = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: ShioSpace.xl) {
                Spacer()

                Text("塩")
                    .font(.custom("DotGothic16-Regular", size: 96))
                    .foregroundStyle(ShioTheme.textPrimary)
                Text("shio")
                    .font(.custom("DepartureMono-Regular", size: 32))
                    .foregroundStyle(ShioTheme.textPrimary)

                Spacer()

                if let error = biometricError {
                    Text(error)
                        .font(ShioFont.callout)
                        .foregroundStyle(ShioTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, ShioSpace.xl)
                }

                LegacyButton(unlockLabel, style: .primary) {
                    Task { await attempt() }
                }
                .padding(.horizontal, ShioSpace.xl)
                .padding(.bottom, ShioSpace.xl)
            }
        }
        .task {
            // Auto-prompt on appear.
            await attempt()
        }
        .transition(.opacity)
    }

    private var unlockLabel: String {
        "Unlock with \(AppLock.methodLabel)"
    }

    private func attempt() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let ok = await AppLock.authenticate(
            reason: "Unlock Shio to access your Macs."
        )
        if ok {
            biometricError = nil
            onUnlocked()
        }
    }
}
