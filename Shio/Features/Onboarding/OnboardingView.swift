import SwiftUI

/// Adaptive Tailscale onboarding. Shown only when no hosts exist.
///
///  - **Fast path**: Tailscale is installed → skip straight to the Mac entry
///    form (`AddHostSheet` in Tailscale mode).
///  - **Guided path**: Tailscale isn't installed → walk the user through
///    install on Mac, then iPhone, then verify. Only show the steps they need.
///
/// All steps live in this single file because the flow is short and the
/// branching needs to read top-to-bottom.
struct OnboardingView: View {

    @Environment(\.modelContext) private var context
    @State private var step: Step = .initial
    @State private var showingAddSheet = false

    enum Step: Hashable {
        case initial
        case welcome
        case introduceTailscale
        case installOnMac
        case installOnIPhone
        case verify
        /// Show the user's public key and have them paste it into their
        /// Mac's authorized_keys file. Required before the first host add —
        /// without this, the SSH connect will fail with auth error.
        case installKey
    }

    var body: some View {
        Group {
            if case .installKey = step {
                // Full-screen key install — its own scroll layout, no wordmark hero.
                PublicKeyView(mode: .onboarding(onComplete: {
                    showingAddSheet = true
                }))
            } else {
                ZStack {
                    ShioColor.Chrome.background.ignoresSafeArea()
                    VStack(spacing: ShioSpace.xl) {
                        Spacer()
                        wordmark
                        Spacer()
                        content
                        Spacer()
                    }
                    .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
                }
            }
        }
        .onAppear { advanceFromInitial() }
        .animation(ShioMotion.standard, value: step)
        .sheet(isPresented: $showingAddSheet, onDismiss: handleSheetDismissed) {
            AddHostSheet(proModeEnabled: false)
        }
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        VStack(spacing: ShioSpace.md) {
            Text("塩")
                .font(ShioFont.kanji(size: 84))
                .foregroundStyle(ShioColor.Text.primary)
            Text("shio")
                .font(ShioFont.wordmark(size: 28))
                .foregroundStyle(ShioColor.Text.primary)
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .initial:
            EmptyView()

        case .welcome:
            stepLayout(
                title: "Your Mac, in your pocket.",
                body: "Shio is a clean, minimal SSH client. Tap to set things up.",
                primary: "Get started",
                primaryAction: { step = nextStepFromWelcome() }
            )

        case .introduceTailscale:
            stepLayout(
                title: "Shio uses Tailscale",
                body: "Tailscale is a free, secure network just for your devices. We'll help you set it up.",
                primary: "Get started",
                primaryAction: { step = .installOnMac }
            )

        case .installOnMac:
            stepLayout(
                title: "Install Tailscale on your Mac",
                body: "Open tailscale.com/download on your Mac and follow the instructions. Sign in with your Google, Microsoft, or GitHub account.",
                primary: "I've installed it on my Mac",
                primaryAction: { step = .installOnIPhone }
            )

        case .installOnIPhone:
            stepLayout(
                title: "Install Tailscale on this iPhone",
                body: "Get Tailscale from the App Store and sign in with the same account you used on your Mac.",
                primary: "Open App Store",
                primaryAction: { TailscaleDetector.openTailscaleOrAppStore() },
                secondary: "I've installed it on my iPhone",
                secondaryAction: { step = .verify }
            )

        case .verify:
            stepLayout(
                title: "Tailscale is set up",
                body: KeyManager.hasKey()
                    ? "Ready to add your Mac."
                    : "One more step — install Shio's SSH key on your Mac so we can sign in.",
                primary: KeyManager.hasKey() ? "Add my Mac" : "Continue",
                primaryAction: {
                    if KeyManager.hasKey() {
                        showingAddSheet = true
                    } else {
                        step = .installKey
                    }
                }
            )

        case .installKey:
            // Rendered full-screen in `body` — this branch never fires.
            EmptyView()
        }
    }

    private func stepLayout(
        title: String,
        body: String,
        primary: String,
        primaryAction: @escaping () -> Void,
        secondary: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: ShioSpace.lg) {
            Text(title)
                .font(ShioFont.title1)
                .foregroundStyle(ShioColor.Text.primary)
                .multilineTextAlignment(.center)
            Text(body)
                .font(ShioFont.body)
                .foregroundStyle(ShioColor.Text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ShioSpace.md)

            VStack(spacing: ShioSpace.sm) {
                ShioButton(primary, action: primaryAction)
                if let secondary, let secondaryAction {
                    ShioButton(secondary, style: .text, action: secondaryAction)
                }
            }
        }
    }

    // MARK: -

    private func advanceFromInitial() {
        guard step == .initial else { return }
        // Always show the welcome step — it's the first impression. From
        // there, branch based on Tailscale presence and key state.
        withAnimation { step = .welcome }
    }

    /// Pick the right next step from welcome. Skips installKey if the user
    /// already has a key (audit finding #7) and skips the Tailscale
    /// walkthrough if Tailscale is already installed.
    private func nextStepFromWelcome() -> Step {
        let tailscaleReady = TailscaleDetector.isInstalled
        let keyReady = KeyManager.hasKey()
        switch (tailscaleReady, keyReady) {
        case (true, true):
            // Everything in place — straight to add-host.
            showingAddSheet = true
            return .verify   // Lands here on sheet dismissal so user has a recoverable state.
        case (true, false):
            return .installKey
        case (false, _):
            return .introduceTailscale
        }
    }

    /// Called when AddHostSheet dismisses. If we're still in onboarding
    /// (the user cancelled instead of saving), step back to a recoverable
    /// state — `.verify` if everything's plumbed, otherwise `.welcome`.
    /// This fixes the audit's #1 finding: previously the user was parked
    /// on PublicKeyView with no way out.
    private func handleSheetDismissed() {
        // If a host was added successfully, RootView will have replaced
        // OnboardingView with the main scene before this fires; the closure
        // here only matters when we're still presented.
        if KeyManager.hasKey() {
            withAnimation { step = .verify }
        } else {
            withAnimation { step = .welcome }
        }
    }
}
