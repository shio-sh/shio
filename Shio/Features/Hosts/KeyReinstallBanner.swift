import SwiftUI

/// Shown at the top of the host list after the user regenerates their SSH
/// key. Reminds them that every Mac in their list needs the new public key
/// pasted into `authorized_keys` before the connection will work again.
///
/// State lives in `KeyManager.needsReinstall` (UserDefaults). Dismissing
/// clears it.
struct KeyReinstallBanner: View {

    /// Read at view-creation; bumped via `bumpToken` so a tap on the dismiss
    /// button re-evaluates without needing a real publisher. This is fine
    /// because the banner only changes on explicit user actions (regenerate
    /// in Settings sets it, dismiss clears it).
    @State private var bumpToken = UUID()

    var body: some View {
        if KeyManager.needsReinstall {
            content
                .id(bumpToken)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: ShioSpace.xs) {
            HStack(spacing: ShioSpace.xs) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShioTheme.warning)
                Text("Your SSH key changed")
                    .font(ShioFont.bodyEmphasis)
                    .foregroundStyle(ShioTheme.textPrimary)
            }
            Text("Each Mac in your list needs the new public key pasted into `~/.ssh/authorized_keys`. Open Settings → SSH Key to copy it.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
            HStack {
                Spacer()
                Button("Got it") {
                    KeyManager.clearReinstallNeeded()
                    bumpToken = UUID()
                }
                .font(ShioFont.bodyEmphasis)
                .foregroundStyle(ShioTheme.textPrimary)
            }
        }
        .padding(ShioSpace.md)
        .background(ShioTheme.warningBg)
        .overlay(
            RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous)
                .strokeBorder(ShioTheme.warning.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous))
        .padding(.horizontal, ShioSpace.lg)
        .padding(.top, ShioSpace.sm)
    }
}
