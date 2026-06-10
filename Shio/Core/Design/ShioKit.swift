import SwiftUI

/// Shio's shared component kit — the "terminal-refined" primitives every rebuilt
/// surface (Projects, Machines, Files, Settings) is assembled from, on both iOS
/// and Mac. Logic is shared; the per-platform dialect (hover on Mac, tap targets
/// on iOS) lives behind small `#if` seams. Built entirely on `ShioTheme` tokens
/// so light/dark + the accent flip come for free.
///
/// Primitives: `ShioStatusDot` · `ShioBrailleSpinner` · `ShioSectionHeader` ·
/// `ShioChip` · `ShioButton`/`ShioButtonStyle` · `ShioCard` · `ShioListRow` ·
/// `ShioRail`. Plus the `ShioStatus` semantic enum that colors dots/chips.

// MARK: - Semantic status

/// The handful of states a dot, chip, or row can carry. Maps to `ShioTheme`'s
/// theme-aware status colors (deepened in light for contrast on the bone canvas).
enum ShioStatus: Equatable {
    case neutral
    case accent
    case success
    case warning
    case danger
    case info

    var tint: Color {
        switch self {
        case .neutral: return ShioTheme.textTertiary
        case .accent:  return ShioTheme.accent
        case .success: return ShioTheme.success
        case .warning: return ShioTheme.warning
        case .danger:  return ShioTheme.danger
        case .info:    return ShioTheme.info
        }
    }

    /// The low-opacity wash behind a chip of this status.
    var wash: Color {
        switch self {
        case .neutral: return ShioTheme.hover
        case .accent:  return ShioTheme.accentBg
        case .success: return ShioTheme.successBg
        case .warning: return ShioTheme.warningBg
        case .danger:  return ShioTheme.dangerBg
        case .info:    return ShioTheme.info.opacity(0.12)
        }
    }
}

// MARK: - Fonts (kit-local, so the kit is self-contained on both targets)

enum ShioKitFont {
    /// Section headers + chips: small, mono, the typographic "terminal" tell.
    static let label    = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// Row titles — sans for chrome legibility, mono is reserved for code/paths.
    static let rowTitle = Font.system(size: 14, weight: .medium, design: .default)
    static let rowMeta  = Font.system(size: 12, weight: .regular, design: .default)
    /// Paths, branches, anything that is literally code.
    static let mono     = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 10.5, weight: .medium, design: .monospaced)
}

// MARK: - Status dot

/// A quiet 6pt status dot. Neutral states read as a hollow ring so only "live"
/// states (success/warning/danger) pull the eye.
struct ShioStatusDot: View {
    var status: ShioStatus = .neutral
    var size: CGFloat = 6
    /// Filled for live states; hollow ring when neutral so it stays calm.
    var filled: Bool = true

    var body: some View {
        Circle()
            .fill(filled ? status.tint : .clear)
            .frame(width: size, height: size)
            .overlay {
                if !filled {
                    Circle().strokeBorder(status.tint.opacity(0.55), lineWidth: 1)
                }
            }
    }
}

// MARK: - Braille spinner

/// One soft braille spinner — the single permitted "something is alive" motion,
/// used for an agent that's actively running. Stateless: the frame is derived
/// from the timeline, so it animates without a `@State` timer and pauses when
/// off-screen. Color defaults to the accent but takes a status for a live agent.
struct ShioBrailleSpinner: View {
    var status: ShioStatus = .accent
    var size: CGFloat = 12

    private static let frames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    private static let fps: Double = 9

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let i = Int(t * Self.fps) % Self.frames.count
            Text(String(Self.frames[i]))
                .font(.system(size: size, weight: .regular, design: .monospaced))
                .foregroundStyle(status.tint)
                .accessibilityLabel("Working")
        }
    }
}

// MARK: - Section header

/// Mono, uppercase, letter-spaced — the terminal-refined section label. Optional
/// trailing accessory (a count chip, an action) sits flush right.
struct ShioSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ShioSpace.sm) {
            Text(title)
                .font(ShioKitFont.label)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(ShioTheme.textTertiary)
            Spacer(minLength: ShioSpace.sm)
            trailing
        }
    }
}

extension ShioSectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

// MARK: - Chip

/// A small mono pill — repo state counts, branch tags, agent labels. Carries a
/// status tint with a matching wash; neutral is a quiet hairline pill.
struct ShioChip: View {
    let text: String
    var status: ShioStatus = .neutral
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            }
            Text(text).font(ShioKitFont.monoSmall)
        }
        .foregroundStyle(status == .neutral ? ShioTheme.textSecondary : status.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(status.wash)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(status == .neutral ? ShioTheme.line : .clear, lineWidth: 1)
        )
        .fixedSize()
    }
}

// MARK: - Button

/// The three button weights in the kit. `primary` = filled accent (ink-on-bone
/// flipping to bone-on-ink); `secondary` = hairline surface; `ghost` = text only.
enum ShioButtonKind { case primary, secondary, ghost }

struct ShioButtonStyle: ButtonStyle {
    var kind: ShioButtonKind = .secondary
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium, design: .default))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 10 : ShioPadding.buttonHorizontal)
            .padding(.vertical, compact ? 6 : ShioPadding.buttonVertical)
            .background(background(pressed: pressed))
            .overlay(
                RoundedRectangle(cornerRadius: ShioRadius.sm, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShioRadius.sm, style: .continuous))
            .opacity(pressed ? 0.85 : 1)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary:   return ShioTheme.background          // flips to read on the accent fill
        case .secondary: return ShioTheme.textPrimary
        case .ghost:     return ShioTheme.accent
        }
    }

    private func background(pressed: Bool) -> some View {
        let fill: Color
        switch kind {
        case .primary:   fill = ShioTheme.accent
        case .secondary: fill = ShioTheme.surface
        case .ghost:     fill = pressed ? ShioTheme.hover : .clear
        }
        return RoundedRectangle(cornerRadius: ShioRadius.sm, style: .continuous).fill(fill)
    }

    private var border: Color {
        switch kind {
        case .primary: return .clear
        case .secondary: return ShioTheme.line2
        case .ghost: return .clear
        }
    }
}

/// Convenience wrapper so call sites read `ShioButton("Connect", .primary) { … }`.
struct ShioButton: View {
    let title: String
    var kind: ShioButtonKind = .secondary
    var icon: String? = nil
    var compact: Bool = false
    let action: () -> Void

    init(_ title: String, _ kind: ShioButtonKind = .secondary,
         icon: String? = nil, compact: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.kind = kind; self.icon = icon
        self.compact = compact; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title)
            }
        }
        .buttonStyle(ShioButtonStyle(kind: kind, compact: compact))
    }
}

// MARK: - Card

/// The surface container — white-on-bone in light, ink-700 in dark, with a
/// hairline and the kit's medium radius. Everything modular sits in one.
struct ShioCard<Content: View>: View {
    var padding: CGFloat = ShioSpace.lg
    @ViewBuilder var content: Content

    init(padding: CGFloat = ShioSpace.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous)
                    .fill(ShioTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShioRadius.md, style: .continuous)
                    .strokeBorder(ShioTheme.line, lineWidth: 1)
            )
    }
}

// MARK: - List row

/// The workhorse row — leading glyph/dot, title (+ optional mono subtitle),
/// trailing accessory. Selected + hover states are kit-managed; hover is a no-op
/// on touch. Use inside `ShioRail` or a plain `VStack`.
struct ShioListRow<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var selected: Bool = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var onTap: (() -> Void)? = nil

    @State private var hovering = false

    init(_ title: String,
         subtitle: String? = nil,
         selected: Bool = false,
         onTap: (() -> Void)? = nil,
         @ViewBuilder leading: () -> Leading = { EmptyView() },
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.onTap = onTap
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: ShioSpace.md) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ShioKitFont.rowTitle)
                    .foregroundStyle(ShioTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(ShioKitFont.mono)
                        .foregroundStyle(ShioTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: ShioSpace.sm)
            trailing
        }
        .padding(.horizontal, ShioSpace.md)
        .padding(.vertical, ShioPadding.rowVertical)
        .frame(minHeight: ShioPadding.tapTargetMin)
        .background(
            RoundedRectangle(cornerRadius: ShioRadius.sm, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onTap?() }
    }

    private var rowFill: Color {
        if selected { return ShioTheme.accentBg }
        if hovering { return ShioTheme.hover }
        return .clear
    }
}

// MARK: - Rail

/// A vertical rail container — the projects rail and the sections sidebar are
/// both `ShioRail`s. Rail-tinted background, optional title header, scrollable.
struct ShioRail<Content: View>: View {
    var title: String? = nil
    var width: CGFloat? = nil
    @ViewBuilder var content: Content

    init(title: String? = nil, width: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ShioSpace.xs) {
            if let title {
                ShioSectionHeader(title)
                    .padding(.horizontal, ShioSpace.md)
                    .padding(.top, ShioSpace.md)
                    .padding(.bottom, ShioSpace.xs)
            }
            ScrollView { VStack(alignment: .leading, spacing: 2) { content }
                .padding(.horizontal, ShioSpace.sm)
                .padding(.vertical, ShioSpace.xs)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ShioTheme.rail)
    }
}
