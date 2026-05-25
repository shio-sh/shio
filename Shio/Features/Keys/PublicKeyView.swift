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

    enum CopyState: Equatable {
        case idle
        case copied
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShioSpace.xl) {
                header
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
        .background(ShioColor.Chrome.background)
        .onAppear { loadKey() }
        .alert("Regenerate SSH key?", isPresented: $confirmingRegenerate) {
            Button("Cancel", role: .cancel) {}
            Button("Regenerate", role: .destructive) { regenerate() }
        } message: {
            Text("Macs using the current key will stop letting you in until you paste the new one into their authorized_keys file.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            Text("Your SSH key")
                .font(ShioFont.title1)
                .foregroundStyle(ShioColor.Text.primary)
            Text("To let Shio sign in to a Mac, that Mac needs to know your public key. Paste the one below into the Mac's `~/.ssh/authorized_keys` file.")
                .font(ShioFont.body)
                .foregroundStyle(ShioColor.Text.secondary)
        }
    }

    private var keyBlock: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            Text("Public key")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)

            Text(publicKeyLine)
                .font(ShioFont.Mono.fingerprint)
                .foregroundStyle(ShioColor.Text.secondary)
                .textSelection(.enabled)
                .padding(ShioSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShioColor.Chrome.surface)
                .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))

            ShioButton(copyState == .copied ? "Copied" : "Copy public key", style: .secondary) {
                UIPasteboard.general.string = publicKeyLine
                animateCopiedState()
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            Text("On your Mac")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)
            Text("Open Terminal and paste this line. It appends the key safely, creating `~/.ssh` if it doesn't exist.")
                .font(ShioFont.body)
                .foregroundStyle(ShioColor.Text.secondary)

            Text(installCommand)
                .font(ShioFont.Mono.fingerprint)
                .foregroundStyle(ShioColor.Text.secondary)
                .textSelection(.enabled)
                .padding(ShioSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShioColor.Chrome.surface)
                .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))

            ShioButton("Copy install command", style: .secondary) {
                UIPasteboard.general.string = installCommand
                animateCopiedState()
            }
        }
    }

    @ViewBuilder
    private var onboardingFooter: some View {
        if case .onboarding(let onComplete) = mode {
            VStack(alignment: .leading, spacing: ShioSpace.sm) {
                ShioButton("I've installed the key") {
                    onComplete()
                }
                Text("You can find this key again in Settings if you set up another Mac later.")
                    .font(ShioFont.footnote)
                    .foregroundStyle(ShioColor.Text.tertiary)
            }
            .padding(.top, ShioSpace.md)
        }
    }

    private var settingsFooter: some View {
        VStack(alignment: .leading, spacing: ShioSpace.sm) {
            ShioButton("Regenerate key", style: .destructive) {
                confirmingRegenerate = true
            }
            Text("Only do this if your key has been compromised, or you want to start over. You'll need to paste the new key on every Mac you use.")
                .font(ShioFont.footnote)
                .foregroundStyle(ShioColor.Text.tertiary)
        }
        .padding(.top, ShioSpace.md)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(ShioFont.callout)
            .foregroundStyle(ShioColor.State.danger)
            .padding(ShioSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ShioColor.State.danger.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))
    }

    // MARK: -

    private func loadKey() {
        do {
            let pk = try KeyManager.currentPublicKey()
            publicKeyLine = OpenSSHFormatter.authorizedKeysLine(publicKey: pk)
            installCommand = OpenSSHFormatter.installCommand(publicKey: pk)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func regenerate() {
        do {
            _ = try KeyManager.regenerate()
            loadKey()
            ShioHaptic.success()
        } catch {
            loadError = error.localizedDescription
            ShioHaptic.error()
        }
    }

    private func animateCopiedState() {
        ShioHaptic.light()
        copyState = .copied
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            copyState = .idle
        }
    }
}
