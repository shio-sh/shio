import SwiftUI
import SwiftData

/// Every project at once — the dashboard zoomed out.
///
/// Deliberately NOT a fifth canvas. The dashboard already exists and already
/// has an empty state; this is that same canvas with nothing selected, so the
/// Mac and iPad gain a way to see across projects (and a way back out of one)
/// without another surface to learn or maintain.
///
/// The cards show what the iPhone's Home already shows, built from the same
/// `ProjectOverviewItem`, so the three platforms cannot drift.
struct ProjectsOverview: View {
    let items: [ProjectOverviewItem]
    let open: (Project) -> Void
    let addProject: () -> Void

    @Environment(\.modelContext) private var context
    /// Held rather than deleted on the spot so the confirmation can name the
    /// project and say what goes with it. Removal lives here, inside the one
    /// view both the Mac and the iPad use, so neither platform can end up
    /// without it again — which is exactly how the Mac shipped unable to
    /// delete a project at all.
    @State private var removeTarget: Project?

    /// Two columns on a Mac or iPad canvas; one when it's narrow.
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items) { item in
                    ProjectOverviewCard(item: item) { open(item.project) }
                        .contextMenu {
                            Button("Remove from Shio…", systemImage: "trash", role: .destructive) {
                                removeTarget = item.project
                            }
                        }
                }
                addCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .confirmationDialog(
            removeTarget.map { "Remove \($0.name) from Shio?" } ?? "Remove project?",
            isPresented: Binding(get: { removeTarget != nil },
                                 set: { if !$0 { removeTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let project = removeTarget {
                    ModelCascade.delete(project: project, context: context)
                    try? context.save()
                }
                removeTarget = nil
            }
            Button("Cancel", role: .cancel) { removeTarget = nil }
        } message: {
            Text("Shio forgets this project, its repos and where they live. No folder, file or session on any machine is touched. This syncs to your other devices.")
        }
    }

    private var addCard: some View {
        Button(action: addProject) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(ShioTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 22, height: 22)
                        .overlay(Text("+").font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(ShioTheme.textTertiary))
                    Text("New project")
                        .font(.system(size: 13))
                        .foregroundStyle(ShioTheme.textSecondary)
                    Spacer(minLength: 0)
                }
                Text("A folder on this Mac, or any machine")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(ShioTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One project in the overview. Identity mark, what state it's in, and where it
/// lives — the three things that decide whether you want to go there.
private struct ProjectOverviewCard: View {
    let item: ProjectOverviewItem
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    ProjectAvatar(item.project, size: 22)
                    Text(item.project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShioTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(hovering ? "open ›" : item.glance.age)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if item.glance.changes > 0 {
                            ShioStatusDot(status: .warning, size: 5)
                        }
                        Text(item.headline)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(item.glance.changes > 0
                                             ? ShioTheme.warning : ShioTheme.textTertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Text(item.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? ShioTheme.hover : ShioTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ShioTheme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
