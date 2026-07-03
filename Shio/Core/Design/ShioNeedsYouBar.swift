import SwiftUI

/// The blocked-agent answer bar — "⚑ Claude · “Run migrations?” ·
/// Approve · y / Deny · n" — one treatment for all eight places it used to
/// be hand-rolled: warning wash, 2pt left rule, the sanctioned pulse, mono
/// mini-actions. The keystroke labels (`· y` / `· n`) are the terminal tell:
/// they say exactly what will be typed.
///
/// Reply plumbing stays per-platform — the closures are injected (iOS rides
/// ActivityFeed.reply / CloudKit; the Mac injects into its own tmux). With no
/// approve/deny (an agent we can see but not answer from here), the bar
/// falls back to a Jump affordance when given one, else quiet text.
struct ShioNeedsYouBar: View {
    let agentName: String
    /// The question it's blocked on, when the detector caught one — quoted.
    var detail: String? = nil
    var approve: (() -> Void)? = nil
    var deny: (() -> Void)? = nil
    /// Open the exact terminal that needs the answer (Home cards / lists).
    var jump: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 9) {
            Text("⚑").font(.system(size: 12)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
            Text(detail.map { "\(agentName) · \u{201C}\($0)\u{201D}" } ?? "\(agentName) is waiting on you")
                .font(.system(size: 12)).foregroundStyle(ShioTheme.warning)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if let approve, let deny {
                ShioMiniButton(title: "Approve · y", status: .success, action: approve)
                ShioMiniButton(title: "Deny · n", status: .danger, action: deny)
                if let jump {
                    ShioMiniButton(title: "→", status: .neutral, action: jump)
                }
            } else if let jump {
                ShioMiniButton(title: "Open terminal", status: .neutral, action: jump)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ShioTheme.warningBg))
        .overlay(alignment: .leading) { Rectangle().fill(ShioTheme.warning).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
