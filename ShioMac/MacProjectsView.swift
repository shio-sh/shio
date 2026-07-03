import SwiftUI
import SwiftData

/// The dashboard canvas — the LANDING when you switch teams. The selected
/// project's overview: a 48pt header (name + quiet counts + Rename/New repo)
/// over the shared `ProjectDashboardView` bento — outline-only cards that
/// fill on hover, laid on a real grid so every edge lands (repos beside
/// grounding; machines full-width below).
struct MacDashboardCanvas: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Environment(\.shioHeaderLeadingInset) private var headerInset
    @State private var renaming = false

    var body: some View {
        Group {
            if let project = model.selectedProject {
                let rows = ProjectRows.rows(for: project)
                let glance = ProjectRows.glance(for: project, rows: rows)
                VStack(spacing: 0) {
                    head(project, glance: glance)
                    ProjectDashboardView(
                        project: project,
                        repos: rows,
                        glance: glance,
                        machines: ProjectRows.machines(for: project),
                        openRepo: { model.open(repo: $0) },
                        addRepo: { model.addRepoToProject = project },
                        openMachines: { model.canvas = .machines },
                        reply: { replyAction($0, key: $1) },
                        // nil host = a pre-self-host local checkout — still this Mac.
                        isLocalHost: { $0.map(MacSelfHost.isThisMac) ?? true }
                    )
                    .id(project.persistentModelID)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioTheme.background)
    }

    /// Inline Approve/Deny exists only when the blocked agent is in THIS Mac's
    /// tmux — a remote one answers from inside its terminal.
    private func replyAction(_ row: RepoRowVM, key: String) -> (() -> Void)? {
        guard row.agent == .waiting,
              let session = MacProjectAgentMonitor.shared.waitingSessionName(forProjectNamed: row.name)
        else { return nil }
        return { MacProjectAgentMonitor.shared.send(key: key, toSession: session) }
    }

    // MARK: header (48pt — the alignment law)

    private func head(_ project: Project, glance: ProjectGlance) -> some View {
        HStack(spacing: 10) {
            MacLogoWell(name: project.name, imageData: project.imageData, size: 22, showsBadge: false) {
                project.imageData = $0
                try? context.save()
            }
            if renaming {
                TextField("Project name", text: Bindable(project).name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: 220)
                    .onSubmit { try? context.save(); renaming = false }
            } else {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ShioTheme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            // The sub compresses first when the canvas gets narrow — middle
            // truncation, never an overflow past the header's bounds.
            Text(headSub(project, glance: glance))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 10)
            ShioButton(renaming ? "Done" : "Rename", .secondary, compact: true) {
                if renaming { try? context.save() }
                renaming.toggle()
            }
            .fixedSize()
            ShioButton("New repo", .primary, compact: true) {
                model.addRepoToProject = project
            }
            .fixedSize()
            MacHeaderIconButton(systemImage: "sidebar.trailing", help: "Inspector (⌘I)",
                                on: model.inspectorOpen) {
                model.inspectorOpen.toggle()
            }
        }
        .padding(.leading, 18 + headerInset)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity)
        .frame(height: MacChrome.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    private func headSub(_ project: Project, glance: ProjectGlance) -> String {
        guard glance.repoCount > 0 else { return "no repos yet" }
        let machines = max(1, Set(project.allCheckouts.map { $0.host?.persistentModelID }).count)
        var sub = "\(glance.repoCount) repo\(glance.repoCount == 1 ? "" : "s")"
            + " · \(machines) machine\(machines == 1 ? "" : "s")"
        if !glance.age.isEmpty { sub += " · updated \(glance.age) ago" }
        return sub
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("塩").font(.system(size: 46)).foregroundStyle(ShioTheme.textTertiary)
            Text("No projects yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ShioTheme.textPrimary)
            Text("A repo on this Mac or any machine — open a folder, or clone from Git.")
                .font(.system(size: 13))
                .foregroundStyle(ShioTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            ShioButton("Add a project", .primary, icon: "plus") { model.showingAddProject = true }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioTheme.background)
    }
}

