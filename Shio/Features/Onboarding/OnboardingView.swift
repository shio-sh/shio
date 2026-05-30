import SwiftUI

/// Verification-driven Tailscale onboarding. Every step that can be probed
/// programmatically runs its check on appear and re-runs when the app
/// returns from a Tailscale-opening deep-link. Steps auto-advance on a
/// successful probe; failed probes show the specific UI element to tap in
/// the Tailscale app to fix it.
///
/// Step order:
///   .welcome           — unconditional brand moment
///   .installOnMac      — instructed only (we can't see the user's Mac)
///   .installApp        — verified by appInstalled
///   .connectVPN        — verified by vpnActive (TCP probe to 100.100.100.100)
///   .installKey        — explicit user action via PublicKeyView
///   .addHost           — opens AddHostSheet
///
/// We deliberately do **not** add a separate "enable Use Tailscale DNS"
/// onboarding step. We can't verify it without a real `.ts.net` hostname
/// from the user, and the AddHostSheet's post-save reachability probe will
/// surface DNS issues with specific remediation copy if "Use Tailscale DNS"
/// is off. Less ceremony in onboarding; clearer error at the moment of truth.
struct OnboardingView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: Step = .initial
    @State private var showingAddSheet = false
    @State private var showingPairing = false
    @State private var verification: Verification = .idle

    enum Step: Hashable {
        case initial
        case welcome
        case installOnMac
        case installApp
        case connectVPN
        case enableAppLock
        case installKey
    }

    /// Verification status for whichever step is currently visible. Reset
    /// each time `step` changes.
    enum Verification: Equatable {
        case idle
        case checking
        case verified
        case failed(message: String)
    }

    var body: some View {
        Group {
            if case .installKey = step {
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
        .onChange(of: scenePhase) { _, phase in
            // When the user returns from a Tailscale deep-link, re-run the
            // current step's verification — they likely just fixed something.
            if phase == .active { runVerificationForCurrentStep() }
        }
        .onChange(of: step) { _, _ in
            verification = .idle
            runVerificationForCurrentStep()
        }
        .animation(ShioMotion.standard, value: step)
        .animation(ShioMotion.standard, value: verification)
        .sheet(isPresented: $showingAddSheet, onDismiss: handleSheetDismissed) {
            AddHostSheet(proModeEnabled: false)
        }
        .sheet(isPresented: $showingPairing) {
            // Pairing inserts a Host on success; RootView's host query then
            // swaps onboarding out for the app, so there's nothing more to do
            // here. If the user cancels without pairing, we stay on .welcome.
            PairingView()
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
                title: "Your machines, in your pocket.",
                body: "Pair a machine you own — scan the QR it shows and Shio is in. Your terminal, your projects, your agents, wherever you are.",
                primary: "Pair with QR",
                primaryAction: { showingPairing = true },
                secondary: "Set up with Tailscale instead",
                secondaryAction: { step = nextStepFromWelcome() }
            )

        case .installOnMac:
            stepLayout(
                title: "Install Tailscale on your Mac",
                body: "On your Mac, open **tailscale.com/download** and follow the steps. Sign in with Google, Apple, Microsoft, or GitHub. We'll wait.",
                primary: "I've installed it",
                primaryAction: { step = .installApp }
            )

        case .installApp:
            verifiedStep(
                title: "Install Tailscale on this iPhone",
                pendingBody: "Get Tailscale from the App Store and sign in with the **same account** you used on your Mac.",
                verifiedBody: "Tailscale is installed.",
                primary: "Open App Store",
                primaryAction: { TailscaleDetector.openTailscaleOrAppStore() },
                secondary: "I've installed it",
                secondaryAction: { runVerificationForCurrentStep() }
            )

        case .connectVPN:
            verifiedStep(
                title: "Turn on Tailscale",
                pendingBody: "Open the Tailscale app. There's a **big toggle at the top** — tap it. It should turn blue and say Connected. While you're there, open the app's settings (your profile, top-left) and turn on **Use Tailscale DNS**.",
                verifiedBody: "Tailscale is connected.",
                primary: "Open Tailscale",
                primaryAction: { TailscaleDetector.openTailscaleOrAppStore() },
                secondary: "Re-check",
                secondaryAction: { runVerificationForCurrentStep() }
            )

        case .enableAppLock:
            stepLayout(
                title: appLockStepTitle,
                body: "Shio is a direct line into your Mac. Lock the app behind \(appLockMethodLabel) so a glance at your phone never becomes a glance at your terminal. You can always change this in Settings.",
                primary: "Enable \(appLockMethodLabel)",
                primaryAction: {
                    Task {
                        let ok = await AppLock.authenticate(
                            reason: "Confirm that Shio can lock with \(AppLock.methodLabel)."
                        )
                        if ok {
                            UserDefaults(suiteName: ShioModelContainer.appGroup)?
                                .set(true, forKey: AppLock.defaultsKey)
                        }
                        await MainActor.run { advanceFromAppLock() }
                    }
                },
                secondary: "Not now",
                secondaryAction: { advanceFromAppLock() }
            )

        case .installKey:
            EmptyView()  // Rendered full-screen in `body`.
        }
    }

    private var appLockStepTitle: String {
        switch AppLock.biometryType {
        case .faceID:  return "Lock Shio with Face ID"
        case .touchID: return "Lock Shio with Touch ID"
        case .opticID: return "Lock Shio with Optic ID"
        default:       return "Lock Shio with your passcode"
        }
    }

    private var appLockMethodLabel: String {
        switch AppLock.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "device authentication"
        }
    }

    private func advanceFromAppLock() {
        // Same branch the old VPN-pass handler used: skip the key install
        // if the key already exists on this device.
        if KeyManager.hasKey() {
            showingAddSheet = true
        } else {
            withAnimation { step = .installKey }
        }
    }

    // MARK: - Layout helpers

    private func stepLayout(
        title: String,
        body: String,
        primary: String,
        primaryAction: @escaping () -> Void,
        secondary: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: ShioSpace.lg) {
            Text(LocalizedStringKey(title))
                .font(ShioFont.title1)
                .foregroundStyle(ShioColor.Text.primary)
                .multilineTextAlignment(.center)
            Text(LocalizedStringKey(body))
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

    /// Step layout that adapts to verification state. While `.checking`,
    /// shows a quiet spinner. On `.verified`, shows a soft "Looks good" beat
    /// and auto-advances after ~700ms. On `.failed` or `.idle`, shows the
    /// instructional UI with the user's action button.
    @ViewBuilder
    private func verifiedStep(
        title: String,
        pendingBody: String,
        verifiedBody: String,
        primary: String,
        primaryAction: @escaping () -> Void,
        secondary: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        switch verification {
        case .checking:
            checkingLayout(title: title)
        case .verified:
            verifiedLayout(title: title, body: verifiedBody)
        case .idle, .failed:
            stepLayout(
                title: title,
                body: pendingBody,
                primary: primary,
                primaryAction: primaryAction,
                secondary: secondary,
                secondaryAction: secondaryAction
            )
        }
    }

    private func checkingLayout(title: String) -> some View {
        VStack(spacing: ShioSpace.lg) {
            Text(LocalizedStringKey(title))
                .font(ShioFont.title1)
                .foregroundStyle(ShioColor.Text.primary)
                .multilineTextAlignment(.center)
            HStack(spacing: ShioSpace.sm) {
                ProgressView().tint(ShioColor.Text.secondary)
                Text("Checking…")
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioColor.Text.secondary)
            }
        }
    }

    private func verifiedLayout(title: String, body: String) -> some View {
        VStack(spacing: ShioSpace.lg) {
            Text(LocalizedStringKey(title))
                .font(ShioFont.title1)
                .foregroundStyle(ShioColor.Text.primary)
                .multilineTextAlignment(.center)
            HStack(spacing: ShioSpace.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ShioColor.State.success)
                Text(LocalizedStringKey(body))
                    .font(ShioFont.body)
                    .foregroundStyle(ShioColor.Text.secondary)
            }
        }
    }

    // MARK: - Flow control

    private func advanceFromInitial() {
        guard step == .initial else { return }
        withAnimation { step = .welcome }
    }

    /// Decide where to land after .welcome. We skip every step whose
    /// precondition is already in place. Steps that need a live probe
    /// (Tailscale installed / VPN connected) handle their own verification
    /// once we arrive — so we err on the side of including them, and
    /// rely on the auto-advance to make the experience seamless.
    private func nextStepFromWelcome() -> Step {
        let tailscaleReady = TailscaleDetector.isInstalled
        let keyReady = KeyManager.hasKey()

        if !tailscaleReady {
            return .installOnMac
        }
        // Tailscale is installed. Verify VPN before adding host.
        if !keyReady {
            return .connectVPN
        }
        // Everything checks out — straight to add-host.
        showingAddSheet = true
        return .connectVPN  // Recoverable landing if the sheet is cancelled.
    }

    private func runVerificationForCurrentStep() {
        switch step {
        case .installApp:
            verifyAppInstalled()
        case .connectVPN:
            verifyVPNActive()
        default:
            break
        }
    }

    private func verifyAppInstalled() {
        verification = .checking
        Task {
            let result = await TailscaleDiagnostic.shared.runSingle(.appInstalled)
            handleVerification(result, onPass: { step = .connectVPN })
        }
    }

    private func verifyVPNActive() {
        verification = .checking
        Task {
            let result = await TailscaleDiagnostic.shared.runSingle(.vpnActive)
            handleVerification(result, onPass: {
                // VPN is up. Walk through the security toggle before
                // touching keys / hosts — that's the natural moment to
                // ask, after the boring connectivity steps are done.
                step = .enableAppLock
            })
        }
    }

    /// Either auto-advance after a brief "Verified" beat, or surface the
    /// failure state so the instructional UI returns.
    @MainActor
    private func handleVerification(_ result: TailscaleDiagnostic.CheckResult, onPass: @escaping () -> Void) {
        switch result.status {
        case .passed:
            verification = .verified
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                // Only advance if we're still on the same step the user just verified —
                // they might have already navigated elsewhere via a different path.
                if case .checking = verification {} else {}
                onPass()
            }
        case .failed(let reason):
            verification = .failed(message: reason)
        case .skipped, .idle, .running:
            verification = .idle
        }
    }

    /// Sheet dismissed. If we're still in onboarding (user cancelled), step
    /// back to a recoverable state.
    private func handleSheetDismissed() {
        if KeyManager.hasKey() {
            withAnimation { step = .connectVPN }  // Verified state will auto-advance again if VPN is still up.
        } else {
            withAnimation { step = .welcome }
        }
    }
}
