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
            // Clearance for the native traffic lights — the window has no
            // titlebar, so they float over the rail's top-left.
            Color.clear.frame(height: 46)

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
                    .padding(.bottom, ShioSpace.sm)
            }

            Text("塩 shio")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .padding(.horizontal, ShioSpace.md + 6)
                .padding(.vertical, ShioSpace.md)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ShioTheme.rail)
        .ignoresSafeArea(edges: .top)
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
        // Terminal keywords, not icons: a ▸ marker carries the selection.
        return Button { model.show(section) } label: {
            HStack(spacing: 8) {
                Text("▸")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 10, alignment: .leading)
                    .foregroundStyle(isSel ? ShioTheme.accent : .clear)
                Text(section.rawValue.lowercased())
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textSecondary)
                Spacer(minLength: 0)
                if section == .projects, model.anyAgentNeedsYou {
                    Text("⚑")
                        .font(.system(size: 11))
                        .foregroundStyle(ShioTheme.warning)
                        .shioNeedsPulse()
                }
            }
            .padding(.horizontal, 10)
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

/// The one sanctioned pulse — needs-you flags breathe, nothing else moves.
private struct ShioNeedsPulse: ViewModifier {
    @State private var dim = false
    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

extension View {
    func shioNeedsPulse() -> some View { modifier(ShioNeedsPulse()) }
}

/// The hairline between the sidebar column and the detail canvas.
struct MacSidebarDivider: View {
    var body: some View {
        Rectangle().fill(ShioTheme.line).frame(width: 1)
    }
}
