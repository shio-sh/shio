import SwiftUI

/// Terminal-coded styling for the Mac org panes. Projects and machines read as
/// shell-prompt lines — a hover caret, a mono name, a dimmed `path · machine`
/// tail, and a right-aligned age — instead of soulless system list rows.

/// A few palette values from docs/design-tokens.md, inlined here because the
/// ShioMac target doesn't pull in the iOS DesignSystem tokens. `bone` is the
/// brand identity color (salt.bone), used sparingly for the caret / This-Mac
/// mark; the rest are semantic state colors for activity dots.
enum MacInk {
    static let bone  = Color(red: 0xE8 / 255, green: 0xDC / 255, blue: 0xC4 / 255) // salt.bone
    static let amber = Color(red: 0xE8 / 255, green: 0x9D / 255, blue: 0x3C / 255) // state.warning
    static let green = Color(red: 0x30 / 255, green: 0xC4 / 255, blue: 0x6D / 255) // state.success
    static let info  = Color(red: 0x5B / 255, green: 0x8D / 255, blue: 0xEF / 255) // state.info
}

/// A quiet, tracked, monospace section label — `PROJECTS`, `REMOTE`.
struct PromptSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .tracking(2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

/// One shell-prompt-style row. The leading slot shows a `▸` caret on hover (or
/// a `pinnedGlyph` like `塩` for This Mac); `statusColor` lights a small
/// activity dot; `age` is right-aligned (e.g. `2h`).
struct PromptRow: View {
    let name: String
    let detail: String
    var age: String = ""
    var statusColor: Color? = nil
    var pinnedGlyph: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(pinnedGlyph ?? (hovering ? "▸" : " "))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(MacInk.bone)
                    .frame(width: 14, alignment: .leading)
                Text(name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .fixedSize()
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let statusColor {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                }
                if !age.isEmpty {
                    Text(age)
                        .font(.system(.caption2, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// shioShortAge / shioPrettyPath moved to shared Shio/Core/Util/ShioFormat.swift
// so the iOS command-center cards can use them too.
