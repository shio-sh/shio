import SwiftUI

/// An agent's presence on a repo or terminal — THE glyph, in one place:
/// ⚑ needs-you (the sanctioned pulse) / braille working / ✓ finished /
/// a quiet idle mark. Previously hand-rolled at ten call sites, which is
/// how dialects drift; now they all speak this one.
///
/// `idle` carries the per-surface dialect: "⎇" on repo rows, "%" on machine
/// shells, nil renders nothing at rest. A site that treats `finished` as
/// quiet (the Mac terminal header) passes the activity pre-mapped
/// (`act == .finished ? .none : act`) — explicit at the call site, not a
/// component mode.
struct ShioPresenceGlyph: View {
    let activity: AgentActivity
    var size: CGFloat = 12
    var idle: String? = "⎇"

    var body: some View {
        switch activity {
        case .waiting:
            Text("⚑")
                .font(.system(size: size))
                .foregroundStyle(ShioTheme.warning)
                .shioNeedsPulse()
        case .running:
            ShioBrailleSpinner(status: .info, size: size)
        case .finished:
            Text("✓")
                .font(.system(size: size, design: .monospaced))
                .foregroundStyle(ShioTheme.success)
        case .none:
            if let idle {
                Text(idle)
                    .font(.system(size: size, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
    }
}
