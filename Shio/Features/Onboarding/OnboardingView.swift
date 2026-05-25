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
        case introduceTailscale
        case installOnMac
        case installOnIPhone
        case verify
    }

    var body: some View {
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
        .onAppear { advanceFromInitial() }
        .sheet(isPresented: $showingAddSheet) {
            AddHostSheet(proModeEnabled: false)
        }
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        VStack(spacing: ShioSpace.sm) {
            Text("塩")
                .font(.system(size: 84))
                .foregroundStyle(ShioColor.Text.primary)
            Text("shio")
                .font(ShioFont.title1)
                .foregroundStyle(ShioColor.Text.primary)
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .initial:
            EmptyView()

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
                title: "You're set",
                body: "Add your Mac next — Shio will reach it over Tailscale.",
                primary: "Add my Mac",
                primaryAction: { showingAddSheet = true }
            )
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
        // Fast path — skip everything if Tailscale is already installed.
        if TailscaleDetector.isInstalled {
            showingAddSheet = true
        } else {
            withAnimation { step = .introduceTailscale }
        }
    }
}
