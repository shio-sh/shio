import SwiftUI
import SwiftData

/// The dashboard canvas — the LANDING when you switch teams. The selected
/// project's overview: a 48pt header (name + quiet counts + Rename/New repo),
/// the glance strip, and the modules. The rail owns project switching; this
/// canvas is pure depth. (The full bento grid lands with the next step.)
struct MacDashboardCanvas: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @State private var renaming = false

    var body: some View {
        Group {
            if let project = model.selectedProject {
                let rows = ProjectRows.rows(for: project)
                VStack(spacing: 0) {
                    head(project, glance: ProjectRows.glance(for: project, rows: rows))
                    MacProjectDashboard(
                        project: project,
                        repos: rows,
                        glance: ProjectRows.glance(for: project, rows: rows),
                        liveAgents: rows.filter { $0.agent != .none },
                        openRepo: { model.open(repo: $0) },
                        addRepo: { model.addRepoToProject = project }
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
            }
            Text(headSub(project, glance: glance))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 10)
            ShioButton(renaming ? "Done" : "Rename", .secondary, compact: true) {
                if renaming { try? context.save() }
                renaming.toggle()
            }
            ShioButton("New repo", .primary, compact: true) {
                model.addRepoToProject = project
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: MacChrome.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    private func headSub(_ project: Project, glance: ProjectGlance) -> String {
        guard glance.repoCount > 0 else { return "no repos yet" }
        let machines = max(1, Set(project.allCheckouts.map { $0.host?.persistentModelID }).count)
        return "\(glance.repoCount) repo\(glance.repoCount == 1 ? "" : "s")"
            + " · \(machines) machine\(machines == 1 ? "" : "s")"
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

// MARK: - Dashboard body

private struct MacProjectDashboard: View {
    @Bindable var project: Project
    let repos: [RepoRowVM]
    let glance: ProjectGlance
    let liveAgents: [RepoRowVM]
    let openRepo: (Repo) -> Void
    let addRepo: () -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \Skill.createdAt) private var allSkills: [Skill]
    @State private var addingSkill = false
    @State private var editingSkill: Skill?
    @State private var commitTarget: RepoRowVM?

    private var globalSkills: [Skill] { allSkills.filter { $0.isGlobal && $0.enabled } }
    private var projectSkills: [Skill] {
        allSkills.filter { $0.project?.persistentModelID == project.persistentModelID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                glanceBar
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 30),
                                    GridItem(.flexible(), spacing: 30)],
                          alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 26) {
                        reposModule
                        agentsModule
                    }
                    VStack(alignment: .leading, spacing: 26) {
                        skillsModule
                        memoryModule
                        integrationsModule
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .sheet(item: $commitTarget) { row in
            let c = row.repo.activeCheckout
            let host = c?.host
            let isLocal = host.map(MacSelfHost.isThisMac) ?? true
            let config: SSHClient.Configuration? = (host != nil && !isLocal)
                ? SSHClient.Configuration(host: host!.hostname, port: host!.port, username: host!.username,
                                          authentication: .systemKeys, initialCols: 80, initialRows: 24)
                : nil
            CommitSheet(repoName: row.name, dirtyCount: GitLineFormatter.make(row.git).dirty,
                        path: c?.path ?? "", config: config,
                        onCommitted: {
                            // Clear the dirty badge right away, not on the next tick.
                            ProjectStatusStore.shared.refresh(ProjectStatusStore.targets(
                                for: [project], isLocalHost: MacSelfHost.isThisMac))
                        })
        }
    }

    // MARK: glance

    private var glanceBar: some View {
        HStack(spacing: 18) {
            if glance.changes > 0 {
                glanceItem { ShioStatusDot(status: .warning) } label: {
                    Text("\(glance.changes)").foregroundStyle(ShioTheme.warning) + Text(" changes")
                }
            }
            if glance.working > 0 {
                glanceItem { ShioBrailleSpinner(status: .info, size: 11) } label: {
                    Text("\(glance.working) agent\(glance.working == 1 ? "" : "s") working").foregroundStyle(ShioTheme.info)
                }
            }
            if glance.needsYou > 0 {
                glanceItem { Text("⚑").foregroundStyle(ShioTheme.warning) } label: {
                    Text("\(glance.needsYou) needs you").foregroundStyle(ShioTheme.warning)
                }
            }
            if glance.changes == 0 && glance.working == 0 && glance.needsYou == 0 {
                Text("all quiet").font(.system(size: 12.5)).foregroundStyle(ShioTheme.textTertiary)
            }
            Spacer()
            if glance.prs > 0 {
                Text("\(glance.prs) open PR\(glance.prs == 1 ? "" : "s")")
                    .font(.system(size: 12.5)).foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
        .padding(.bottom, 20)
    }

    private func glanceItem<Icon: View, Label: View>(@ViewBuilder icon: () -> Icon,
                                                      @ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: 7) { icon(); label().foregroundStyle(ShioTheme.textSecondary) }
    }

    // MARK: repos (LIVE)

    private var reposModule: some View {
        VStack(alignment: .leading, spacing: 4) {
            ShioSectionHeader("repos") {
                Button("+ add") { addRepo() }
                    .buttonStyle(.plain)
                    .font(ShioKitFont.rowMeta)
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            .padding(.bottom, 4)
            if repos.isEmpty {
                moduleHint("No repos yet — add one to this project.")
            } else {
                ForEach(repos) { row in
                    RepoRowView(row: row, open: { openRepo(row.repo) }, onCommit: { commitTarget = row },
                                openOn: { checkout in
                                    // Mark the chosen machine most-recent → it becomes the
                                    // active checkout → open() picks it up. No model change.
                                    checkout.lastOpenedAt = .now
                                    try? context.save()
                                    openRepo(row.repo)
                                })
                }
            }
        }
    }

    // MARK: agents (LIVE from local monitor; approve/deny land with remote control)

    private var agentsModule: some View {
        VStack(alignment: .leading, spacing: 4) {
            ShioSectionHeader("agents").padding(.bottom, 4)
            if liveAgents.isEmpty {
                moduleHint("No agents running. Open a terminal and start one.")
            } else {
                ForEach(liveAgents) { row in AgentRowView(row: row, jump: { openRepo(row.repo) }) }
            }
        }
    }

    // MARK: stubbed modules (designed; fill in P5+)

    private var skillsModule: some View {
        VStack(alignment: .leading, spacing: 4) {
            ShioSectionHeader("skills") {
                Button("+ add") { addingSkill = true }
                    .buttonStyle(.plain).font(ShioKitFont.rowMeta).foregroundStyle(ShioTheme.textTertiary)
            }.padding(.bottom, 4)
            if globalSkills.isEmpty && projectSkills.isEmpty {
                moduleHint("No skills yet — add one here, or build the global library in Settings.")
            } else {
                ForEach(globalSkills) { skill in skillRow(skill, scope: "global") }
                ForEach(projectSkills) { skill in skillRow(skill, scope: "project") }
            }
        }
        .sheet(isPresented: $addingSkill) { SkillEditor(skill: nil, project: project) }
        .sheet(item: $editingSkill) { skill in SkillEditor(skill: skill, project: skill.project) }
    }

    private func skillRow(_ skill: Skill, scope: String) -> some View {
        Button { editingSkill = skill } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(ShioTheme.success)
                Text(skill.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
                Spacer()
                ShioChip(text: scope, status: scope == "project" ? .accent : .neutral)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var memoryModule: some View {
        VStack(alignment: .leading, spacing: 4) {
            ShioSectionHeader("memory & context").padding(.bottom, 4)
            stubRow(glyph: "✎", name: "notes",
                    meta: (project.notes?.isEmpty == false) ? "edited" : "empty")
        }
    }

    private var integrationsModule: some View {
        VStack(alignment: .leading, spacing: 4) {
            ShioSectionHeader("integrations").padding(.bottom, 4)
            stubRow(glyph: "◐", name: "GitHub", meta: "connect ›", metaColor: ShioTheme.info)
            stubRow(glyph: "◑", name: "Linear", meta: "connect ›", metaColor: ShioTheme.info)
        }
    }

    private func moduleHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func stubRow(glyph: String, name: String, meta: String,
                         metaColor: Color = ShioTheme.textTertiary) -> some View {
        HStack(spacing: 10) {
            Text(glyph).font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary).frame(width: 14)
            Text(name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
            Spacer()
            Text(meta).font(.system(size: 12)).foregroundStyle(metaColor)
        }
        .padding(.horizontal, 8).padding(.vertical, 9)
    }
}

// MARK: - Repo row

private struct RepoRowView: View {
    let row: RepoRowVM
    let open: () -> Void
    var onCommit: (() -> Void)? = nil
    var openOn: ((ProjectCheckout) -> Void)? = nil
    @State private var hovering = false

    private func machineLabel(_ c: ProjectCheckout) -> String {
        (c.host.map(MacSelfHost.isThisMac) ?? true) ? "This Mac" : (c.host?.name ?? "Unknown")
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(row.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
                    if let pr = row.prs.first(where: { $0.state == "OPEN" }) {
                        ShioChip(text: "PR #\(pr.number)", status: pr.isDraft ? .neutral : .info)
                    }
                    Spacer()
                    if hovering {
                        Text("open ›").font(.system(size: 12)).foregroundStyle(ShioTheme.textSecondary)
                    }
                }
                gitLine
            }
            .padding(.horizontal, 8).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? ShioTheme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            let checkouts = row.repo.checkouts ?? []
            if checkouts.count > 1, let openOn {
                Menu("Open on") {
                    ForEach(checkouts, id: \.persistentModelID) { c in
                        Button(machineLabel(c)) { openOn(c) }
                    }
                }
            }
            if GitLineFormatter.make(row.git).dirty > 0, let onCommit {
                Button("Commit & push…", systemImage: "arrow.up", action: onCommit)
            }
        }
    }

    @ViewBuilder private var gitLine: some View {
        let m = GitLineFormatter.make(row.git)
        HStack(spacing: 12) {
            if row.agent == .running {
                HStack(spacing: 6) {
                    ShioBrailleSpinner(status: .info, size: 11)
                    Text(agentSummary).foregroundStyle(ShioTheme.info).lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                Text("⎇").foregroundStyle(ShioTheme.textTertiary)
                Text(m.branch).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(m.state == .loading || m.state == .unreachable
                                     ? ShioTheme.textTertiary : ShioTheme.textSecondary)
            }
            if m.hasTracking {
                if m.ahead > 0 { seg("↑\(m.ahead)") }
                if m.behind > 0 { seg("↓\(m.behind)") }
                if m.dirty > 0 {
                    HStack(spacing: 6) { ShioStatusDot(status: .warning)
                        Text("\(m.dirty)").foregroundStyle(ShioTheme.warning) }
                } else {
                    Text("clean").foregroundStyle(ShioTheme.success)
                }
            }
            Spacer(minLength: 0)
            Text(row.machines).foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 12, design: .monospaced))
        .monospacedDigit()
    }

    private func seg(_ t: String) -> some View {
        Text(t).foregroundStyle(ShioTheme.textSecondary)
    }

    private var agentSummary: String {
        if let d = row.agentDetail, !d.isEmpty { return d }
        return row.agentName ?? "working…"
    }
}

// MARK: - Agent row

private struct AgentRowView: View {
    let row: RepoRowVM
    let jump: () -> Void
    @State private var hovering = false

    private var needsYou: Bool { row.agent == .waiting }

    var body: some View {
        HStack(spacing: 11) {
            if needsYou {
                Text("⚑").font(.system(size: 12)).foregroundStyle(ShioTheme.warning)
            } else {
                ShioBrailleSpinner(status: .info, size: 11)
            }
            Text("\(row.agentName ?? "Agent") · \(row.name)")
                .font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1).fixedSize()
            if let detail = row.agentDetail, !detail.isEmpty {
                Text(detail).font(.system(size: 12))
                    .foregroundStyle(needsYou ? ShioTheme.warning : ShioTheme.textTertiary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            ShioButton("jump ›", .secondary, compact: true) { jump() }
        }
        .padding(.horizontal, 8).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(needsYou ? ShioTheme.warningBg : (hovering ? ShioTheme.hover : .clear))
        )
        .overlay(alignment: .leading) {
            if needsYou { Rectangle().fill(ShioTheme.warning).frame(width: 2) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering = $0 }
    }
}
