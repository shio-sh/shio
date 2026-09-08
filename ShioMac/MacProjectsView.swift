import SwiftUI
import SwiftData

/// The dashboard canvas — the LANDING when you switch teams. The selected
/// project's overview: a 48pt header (name + quiet counts + Rename/New repo)
/// over the shared `ProjectDashboardView` bento — outline-only cards that
/// fill on hover, laid on a real grid so every edge lands (repos above
/// machines, which run full-width below).
struct MacDashboardCanvas: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Environment(\.shioHeaderLeadingInset) private var headerInset
    @State private var renaming = false
    /// The phone offer waits until a project exists, so it lands after Shio has
    /// actually done something rather than asking for a second device up front.
    @State private var phoneOfferDismissed =
        UserDefaults.standard.bool(forKey: MacPhoneOffer.dismissedKey)

    var body: some View {
        Group {
            if let project = model.selectedProject {
                let rows = ProjectRows.rows(for: project)
                let glance = ProjectRows.glance(for: project, rows: rows)
                VStack(spacing: 0) {
                    head(project, glance: glance)
                    if !phoneOfferDismissed {
                        MacPhoneOffer(
                            onPair: { model.canvas = .machines; model.showingPairing = true },
                            onDismiss: { phoneOfferDismissed = true }
                        )
                        .padding(.horizontal, 26)
                        .padding(.top, 14)
                    }
                    ProjectDashboardView(
                        project: project,
                        repos: rows,
                        glance: glance,
                        machines: ProjectRows.machines(for: project),
                        openRepo: { model.open(repo: $0) },
                        addRepo: { model.addRepoToProject = project },
                        openMachines: { model.canvas = .machines },
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

    /// The last screen of the guided pass, which is also what an empty Mac
    /// shows from then on. Ranked ways in rather than one button and a sentence
    /// of jargon: the old copy said "a repo on this Mac or any machine, open a
    /// folder or clone from Git", which is three concepts and two words the
    /// user has not met yet.
    private var emptyState: some View {
        VStack(spacing: 9) {
            Text("塩").font(.system(size: 38)).foregroundStyle(ShioTheme.textTertiary)
            Text("Start with a folder")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ShioTheme.textPrimary)
            Text("Open one and Shio keeps a terminal there, ready on this Mac and on your phone.")
                .font(.system(size: 12.5))
                .foregroundStyle(ShioTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.bottom, 4)
            VStack(spacing: 7) {
                emptyChoice("Open a folder on this Mac", "The usual way to start",
                            glyph: "folder", lead: true) { model.showingAddProject = true }
                emptyChoice("Clone from a GitHub link", "Or GitLab, Bitbucket, or your own server",
                            glyph: "arrow.down.circle") { model.showingAddProject = true }
                emptyChoice("Connect another machine", "A server, a Pi, or another Mac that stays awake",
                            glyph: "desktopcomputer") { model.showingAddHost = true }
            }
            .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioTheme.background)
    }

    private func emptyChoice(_ head: String, _ sub: String, glyph: String,
                             lead: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: glyph)
                    .font(.system(size: 13))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .frame(width: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(head)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(ShioTheme.textPrimary)
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(ShioTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(lead ? ShioTheme.hover : ShioTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ShioTheme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

