import SwiftUI

/// Shared chrome bones for the Slack frame: the canvas header (the one fixed
/// height every center/inspector header shares), the hairline divider, and the
/// single sanctioned pulse. The rail itself lives in MacRail.swift.

/// Every canvas header is EXACTLY this tall, so the bottom hairline forms one
/// continuous line across the window — center and inspector alike. Never size
/// a header by padding (the alignment law).
enum MacChrome {
    static let headerHeight: CGFloat = 48
}

/// The center canvas's top bar: optional presence glyph, title, quiet mono
/// metadata, trailing actions. Bottom hairline included.
struct MacCanvasHeader<Leading: View, Trailing: View>: View {
    let title: String
    var sub: String? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(title: String,
         sub: String? = nil,
         @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.sub = sub
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            leading()
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1)
            if let sub {
                Text(sub)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: MacChrome.headerHeight)
        .background(ShioTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }
}

/// A quiet glyph button for canvas headers (◫ split, ▤ inspector, ✕ close).
struct MacHeaderIconButton: View {
    let glyph: String
    var help: String = ""
    var on: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(on ? ShioTheme.accent
                                 : (hovering ? ShioTheme.textPrimary : ShioTheme.textTertiary))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? ShioTheme.accentBg : (hovering ? ShioTheme.hover : .clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The inline micro-action — Approve · y / Deny · n on a needs-you row.
/// Mono, hairline, status-tinted; never a heavy fill.
struct MacMiniButton: View {
    let title: String
    var status: ShioStatus = .neutral
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(status == .neutral ? ShioTheme.textSecondary : status.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? ShioTheme.hover : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(status == .neutral ? ShioTheme.line2 : status.tint.opacity(0.35),
                                      lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "⚑ Codex is waiting on you · Approve · Deny" — the blocked-agent bar shown
/// over a conversation (and echoed by the dashboard's needs-you row).
struct MacNeedBar: View {
    let agentName: String
    let approve: () -> Void
    let deny: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("⚑")
                .font(.system(size: 12))
                .foregroundStyle(ShioTheme.warning)
                .shioNeedsPulse()
            Text("\(agentName) is waiting on you")
                .font(.system(size: 12.5))
                .foregroundStyle(ShioTheme.textPrimary)
            Spacer(minLength: 10)
            MacMiniButton(title: "Approve · y", status: .success, action: approve)
            MacMiniButton(title: "Deny · n", status: .danger, action: deny)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(ShioTheme.warningBg)
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(ShioTheme.warning).frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// The hairline between the rail and the center canvas.
struct MacSidebarDivider: View {
    var body: some View {
        Rectangle().fill(ShioTheme.line).frame(width: 1)
    }
}
