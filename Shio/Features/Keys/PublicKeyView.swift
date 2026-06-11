import SwiftUI
import CryptoKit
import UIKit

/// Shows the user the public half of Shio's SSH key so they can paste it
/// into `~/.ssh/authorized_keys` on the Mac they want to reach.
///
/// Two presentation contexts:
///   - **Onboarding step** — full screen, with a primary "Copy install
///     command" CTA and an explanation of what to do with it. The
///     `onComplete` callback advances the onboarding flow.
///   - **Settings** — same content rendered without the CTA, plus a
///     "Regenerate key" destructive option.
struct PublicKeyView: View {
    enum Mode {
        /// Shown in onboarding before the user adds their first host.
        case onboarding(onComplete: () -> Void)
        /// Shown in Settings → SSH Key.
        case settings
    }

    let mode: Mode

    @State private var publicKeyLine: String = ""
    @State private var installCommand: String = ""
    @State private var copyState: CopyState = .idle
    @State private var loadError: String?
    @State private var confirmingRegenerate = false
    @State private var remoteLoginWhyExpanded: Bool = false

    enum CopyState: Equatable {
        case idle
        case copied
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShioSpace.xl) {
                header
                remoteLoginSection
                keyBlock
                instructions
                if case .onboarding = mode {
                    onboardingFooter
                }
                if case .settings = mode {
                    settingsFooter
                }
                if let loadError {
                    errorBanner(loadError)
                }
            }
            .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
            .padding(.vertical, ShioSpace.xl)
        }
        .background(ShioTheme.background)
        .task { await ensureKeyAndLoad() }
        .alert("Regenerate SSH key?", isPresented: $confirmingRegenerate) {
            Button("Cancel", role: .cancel) {}
            Button("Regenerate", role: .destructive) { Task { await regenerate() } }
        } message: {
            Text("Macs using the current key will stop letting you in until you paste the new one into their authorized_keys file.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            Text("Your SSH key")
                .font(ShioFont.title1)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("To let Shio sign in to a Mac, that Mac needs to know your public key. Paste the one below into the Mac's `~/.ssh/authorized_keys` file.")
                .font(ShioFont.body)
                .foregroundStyle(ShioTheme.textSecondary)
        }
    }

    /// Step 1 of the user-side setup. Without Remote Login enabled on the
    /// Mac, even a correctly-installed key gets a `Connection refused` on
    /// port 22 — so we surface this *before* the key block, which is step 2.
    private var remoteLoginSection: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            Text("First, enable Remote Login on your Mac")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("On your Mac, open **System Settings → General → Sharing**. Turn on **Remote Login**. Under \"Allow access for\", make sure your user account is included.")
                .font(ShioFont.body)
                .foregroundStyle(ShioTheme.textSecondary)

            Button {
                withAnimation(ShioMotion.standard) { remoteLoginWhyExpanded.toggle() }
            } label: {
                HStack(spacing: ShioSpace.xs) {
                    Text(remoteLoginWhyExpanded ? "Why?" : "Why?")
                        .font(ShioFont.callout)
                    Image(systemName: remoteLoginWhyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(ShioTheme.textTertiary)
            }
            .buttonStyle(.plain)

            if remoteLoginWhyExpanded {
                Text("Remote Login is what starts the SSH server on your Mac. Without it, your Mac refuses Shio's connection — even with the right key.")
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textSecondary)
                    .padding(.top, ShioSpace.xs)
            }
        }
    }

    private var keyBlock: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            Text("Public key")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)

            Text(publicKeyLine)
                .font(ShioFont.Mono.fingerprint)
                .foregroundStyle(ShioTheme.textSecondary)
                .textSelection(.enabled)
                .padding(ShioSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShioTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))

            LegacyButton(copyState == .copied ? "Copied" : "Copy public key", style: .secondary) {
                UIPasteboard.general.string = publicKeyLine
                animateCopiedState()
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            Text("Then install the key")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("On your Mac, open Terminal and paste this line. It appends the key safely, creating `~/.ssh` if it doesn't exist.")
                .font(ShioFont.body)
                .foregroundStyle(ShioTheme.textSecondary)

            Text(installCommand)
                .font(ShioFont.Mono.fingerprint)
                .foregroundStyle(ShioTheme.textSecondary)
                .textSelection(.enabled)
                .padding(ShioSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShioTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))

            LegacyButton("Copy install command", style: .secondary) {
                UIPasteboard.general.string = installCommand
                animateCopiedState()
            }
        }
    }

    @ViewBuilder
    private var onboardingFooter: some View {
        if case .onboarding(let onComplete) = mode {
            VStack(alignment: .leading, spacing: ShioSpace.sm) {
                LegacyButton("I've installed the key") {
                    onComplete()
                }
                Text("You can find this key again in Settings if you set up another Mac later.")
                    .font(ShioFont.footnote)
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            .padding(.top, ShioSpace.md)
        }
    }

    private var settingsFooter: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            LegacyButton("Regenerate key", style: .destructive) {
                confirmingRegenerate = true
            }
            Text("Only do this if your key has been compromised, or you want to start over. You'll need to paste the new key on every Mac you use.")
                .font(ShioFont.footnote)
                .foregroundStyle(ShioTheme.textTertiary)
        }
        .padding(.top, ShioSpace.md)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(ShioFont.callout)
            .foregroundStyle(ShioTheme.danger)
            .padding(ShioSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ShioTheme.danger.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))
    }

    // MARK: -

    /// Reaches the screen → ensure a key exists, then load its public half
    /// for display. Runs the (potentially blocking) Keychain operations on
    /// a background task so SwiftUI's main thread stays responsive.
    private func ensureKeyAndLoad() async {
        apply(await Self.lines(regenerate: false))
    }

    private func regenerate() async {
        let result = await Self.lines(regenerate: true)
        apply(result)
        if case .success = result { ShioHaptic.success() } else { ShioHaptic.error() }
    }

    @MainActor private func apply(_ result: Result<(line: String, install: String), any Error>) {
        switch result {
        case .success(let pair): publicKeyLine = pair.line; installCommand = pair.install; loadError = nil
        case .failure(let error): loadError = error.localizedDescription
        }
    }

    /// Load (or regenerate) the **active** key's public half — the opt-in
    /// Secure Enclave P-256 key when enabled, else the Ed25519 key — and format
    /// both the authorized_keys line and the install command for it.
    private static func lines(regenerate: Bool) async -> Result<(line: String, install: String), any Error> {
        await Task.detached(priority: .userInitiated) {
            do {
                if KeyManager.useEnclaveKey && KeyManager.enclaveAvailable() {
                    let pk = try (regenerate ? KeyManager.regenerateEnclave()
                                             : KeyManager.generateEnclaveIfNeeded()).publicKey
                    return .success((OpenSSHFormatter.authorizedKeysLine(p256PublicKey: pk),
                                     OpenSSHFormatter.installCommand(p256PublicKey: pk)))
                } else {
                    let pk = try (regenerate ? KeyManager.regenerate()
                                             : KeyManager.generateIfNeeded()).publicKey
                    return .success((OpenSSHFormatter.authorizedKeysLine(publicKey: pk),
                                     OpenSSHFormatter.installCommand(publicKey: pk)))
                }
            } catch {
                return .failure(error)
            }
        }.value
    }

    private func animateCopiedState() {
        ShioHaptic.light()
        copyState = .copied
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            copyState = .idle
        }
    }
}
