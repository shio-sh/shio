import SwiftUI

/// Shared chrome bones for the Slack frame: the canvas header (the one fixed
/// height every center/inspector header shares), the hairline divider, and the
/// single sanctioned pulse. The rail itself lives in MacRail.swift.

/// Every canvas header is EXACTLY this tall, so the bottom hairline forms one
/// continuous line across the window — center and inspector alike. Never size
/// a header by padding (the alignment law).
enum MacChrome {
    static let headerHeight: CGFloat = 48
    /// Leading clearance a canvas header needs when the rail is collapsed —
    /// the traffic lights + the floating sidebar toggle live in that strip.
    static let lightsClearance: CGFloat = 126
}

private struct ShioHeaderInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Extra leading inset for canvas headers — MacShell sets it to
    /// `MacChrome.lightsClearance` while the rail is collapsed so titles
    /// never run under the traffic lights or the sidebar toggle.
    var shioHeaderLeadingInset: CGFloat {
        get { self[ShioHeaderInsetKey.self] }
        set { self[ShioHeaderInsetKey.self] = newValue }
    }
}

/// The center canvas's top bar: optional presence glyph, title, quiet mono
/// metadata, trailing actions. Bottom hairline included.
struct MacCanvasHeader<Leading: View, Trailing: View>: View {
    let title: String
    var sub: String? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.shioHeaderLeadingInset) private var leadingInset

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
        .padding(.leading, 18 + leadingInset)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity)
        .frame(height: MacChrome.headerHeight)
        .background(ShioTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }
}

/// A quiet icon button for canvas headers (split, inspector, close) — real
/// SF Symbols at the standard toolbar size, never tiny text glyphs.
struct MacHeaderIconButton: View {
    let systemImage: String
    var size: CGFloat = 14
    var help: String = ""
    var on: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(on ? ShioTheme.accent
                                 : (hovering ? ShioTheme.textPrimary : ShioTheme.textSecondary))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? ShioTheme.accentBg : (hovering ? ShioTheme.hover : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The sidebar toggle (⌘\) — rides the switcher row while the rail is open,
/// floats beside the traffic lights when it's collapsed.
struct MacRailToggleButton: View {
    @Bindable var model: MacTerminalModel
    /// `.trailing` in the rail so the glyph lands exactly on the rail's
    /// trailing axis; centered when floating beside the lights.
    var glyphAlignment: Alignment = .center
    @State private var hovering = false

    var body: some View {
        Button {
            model.showingProjectMenu = false
            withAnimation(.easeOut(duration: 0.15)) { model.sidebarCollapsed.toggle() }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(hovering ? ShioTheme.textPrimary : ShioTheme.textSecondary)
                .frame(width: 28, height: 28, alignment: glyphAlignment)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? ShioTheme.hover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
        .onHover { hovering = $0 }
        .help(model.sidebarCollapsed ? "Show sidebar (⌘\\)" : "Hide sidebar (⌘\\)")
    }
}

/// The hairline between the rail and the center canvas.
struct MacSidebarDivider: View {
    var body: some View {
        Rectangle().fill(ShioTheme.line).frame(width: 1)
    }
}
