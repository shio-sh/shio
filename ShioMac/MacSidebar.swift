import SwiftUI

/// THE sidebar — Shio's own, the only one. Sections (terminal / projects /
/// machines / files) live at the top in the rail's own language; the active
/// section's contextual rows render below; the whole column collapses via
/// `model.sidebarCollapsed` (title-bar button, or ⌃⌘S). Replaces both the
/// system NavigationSplitView sidebar and the title-bar section switcher.
struct MacSidebarColumn<Content: View, Actions: View>: View {
    var model: MacTerminalModel
    let title: String
    var width: CGFloat = 238
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    init(model: MacTerminalModel,
         title: String,
         width: CGFloat = 238,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.model = model
        self.title = title
        self.width = width
        self.content = content
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacSectionsNav(model: model)

            Rectangle().fill(ShioTheme.line).frame(height: 1)
                .padding(.horizontal, ShioSpace.sm)

            HStack(spacing: 4) {
                ShioSectionHeader(title)
                Spacer(minLength: 4)
                actions()
            }
            .padding(.horizontal, ShioSpace.md)
            .padding(.top, ShioSpace.md)
            .padding(.bottom, ShioSpace.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) { content() }
                    .padding(.horizontal, ShioSpace.sm)
                    .padding(.bottom, ShioSpace.md)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ShioTheme.rail)
    }
}

/// The section rows at the top of the sidebar — same row language as the
/// rails below them (accent + accentBg pill for the active section).
struct MacSectionsNav: View {
    var model: MacTerminalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(MacSection.allCases) { section in
                row(section)
            }
        }
        .padding(.horizontal, ShioSpace.sm)
        .padding(.top, ShioSpace.sm)
        .padding(.bottom, ShioSpace.sm)
    }

    private func row(_ section: MacSection) -> some View {
        let isSel = model.section == section
        return Button { model.show(section) } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textTertiary)
                Text(section.rawValue.lowercased())
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSel ? ShioTheme.accentBg : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The hairline between the sidebar column and the detail canvas.
struct MacSidebarDivider: View {
    var body: some View {
        Rectangle().fill(ShioTheme.line).frame(width: 1)
    }
}
