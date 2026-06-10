import SwiftUI
import SwiftData

/// Projects on the Mac — master/detail, the terminal-refined language. The
/// projects list is a slim **rail** (switch projects + glance who-needs-you);
/// the selected project's **dashboard is always the canvas** — no click-through.
/// Open Projects and you're already in the depth.
///
/// Live now: the **repos** module (git state from `ProjectStatusStore`) and the
/// **agents** module (local `MacProjectAgentMonitor`). Skills / memory & context
/// / integrations are designed-but-stubbed shells that fill in across P5+.
struct MacProjectsView: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @State private var agents = MacProjectAgentMonitor.shared
    @State private var selected: Project?
    @State private var addRepoTarget: Project?
    private let status = ProjectStatusStore.shared

    var body: some View {
        Group {
            if projects.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    ShioRail(title: "projects", width: 238) {
                        ForEach(sorted) { project in
                            railItem(project)
                        }
                    }
                    .overlay(alignment: .topTrailing) { addButton }
                    Rectangle().fill(ShioTheme.line).frame(width: 1)
                    dashboard
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ShioTheme.background)
                }
            }
        }
        .sheet(isPresented: $model.showingAddProject) { MacAddProjectForm(model: model) }
        .sheet(item: $addRepoTarget) { proj in MacAddProjectForm(model: model, targetProject: proj) }
        .onAppear { ensureSelection(); refreshStatus() }
        .onChange(of: projects.count) { _, _ in ensureSelection() }
        // Cheap keep-fresh while Projects is on screen: this view only exists
        // when the section is selected, so the timer pauses the moment you leave.
        // warmOnly so it never wakes a sleeping remote.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                status.refresh(ProjectStatusStore.targets(
                    for: projects, isLocalHost: MacSelfHost.isThisMac, warmOnly: true))
            }
        }
    }

    // MARK: rail

    private func railItem(_ project: Project) -> some View {
        let activity = projectAgent(project)
        let isSel = selected?.persistentModelID == project.persistentModelID
        return Button { selected = project; refreshStatus() } label: {
            HStack(spacing: 9) {
                projectMark(project, active: isSel || activity != .none)
                Text(project.name)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                railIndicator(activity)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSel ? ShioTheme.accentBg : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Add repo…") { addRepoTarget = project }
            Divider()
            Button("Remove from Shio", role: .destructive) { remove(project) }
        }
    }

    private func projectMark(_ project: Project, active: Bool) -> some View {
        Text(String(project.name.first ?? "•").uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(active ? ShioTheme.accent : ShioTheme.textTertiary)
            .frame(width: 18, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(active ? ShioTheme.accentBg : ShioTheme.hover)
            )
    }

    @ViewBuilder private func railIndicator(_ activity: AgentActivity) -> some View {
        switch activity {
        case .running:  ShioBrailleSpinner(status: .info, size: 11)
        case .waiting:  Text("⚑").font(.system(size: 11)).foregroundStyle(ShioTheme.warning)
        case .finished: ShioStatusDot(status: .success)
        case .none:     EmptyView()
        }
    }

    private var addButton: some View {
        Button { model.showingAddProject = true } label: {
            Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                .foregroundStyle(ShioTheme.textTertiary)
                .padding(10)
        }
        .buttonStyle(.plain)
        .help("Add a project")
    }

    // MARK: dashboard

    @ViewBuilder private var dashboard: some View {
        if let project = selected ?? sorted.first {
            MacProjectDashboard(
                project: project,
                repos: repoRows(project),
                glance: glance(project),
                liveAgents: liveAgents(project),
                openRepo: { model.open(repo: $0) },
                openTerminal: { open(project) },
                addRepo: { addRepoTarget = project }
            )
            .id(project.persistentModelID)
        } else {
            Color.clear
        }
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

    // MARK: selection + data

    /// Needs-you first, then running, then most-recently-opened.
    private var sorted: [Project] {
        projects.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (a.lastOpenedAt ?? .distantPast) > (b.lastOpenedAt ?? .distantPast)
        }
    }
    private func rank(_ p: Project) -> Int {
        switch projectAgent(p) {
        case .waiting: return 0
        case .running: return 1
        default:       return 2
        }
    }

    private func ensureSelection() {
        if let sel = selected, projects.contains(where: { $0.persistentModelID == sel.persistentModelID }) { return }
        selected = sorted.first
    }

    private func remove(_ project: Project) {
        if selected?.persistentModelID == project.persistentModelID { selected = nil }
        context.delete(project)
        try? context.save()
        ensureSelection()
    }

    private func open(_ project: Project) {
        project.lastOpenedAt = .now
        try? context.save()
        model.open(project: project)
    }

    private func refreshStatus() {
        status.refresh(ProjectStatusStore.targets(for: projects, isLocalHost: MacSelfHost.isThisMac))
    }

    private func repoRows(_ project: Project) -> [RepoRowVM] {
        project.sortedRepos.map { repo in
            RepoRowVM(id: repo.persistentModelID, repo: repo, name: repo.name,
                      machines: machinesText(repo), git: gitProbe(repo),
                      agent: localAgentActivity(repo),
                      agentName: agentSnapshot(repo)?.agentName,
                      agentDetail: agentSnapshot(repo)?.detail)
        }
    }

    private func gitProbe(_ repo: Repo) -> GitProbe? {
        guard let c = repo.activeCheckout else { return nil }
        return status.status(forHost: c.host, path: c.path)?.probe
    }

    private func machinesText(_ repo: Repo) -> String {
        let names = (repo.checkouts ?? []).map { c -> String in
            guard let h = c.host else { return "this mac" }
            return MacSelfHost.isThisMac(h) ? "this mac" : h.name
        }
        var seen = Set<String>(); var unique: [String] = []
        for n in names where !seen.contains(n) { seen.insert(n); unique.append(n) }
        return unique.isEmpty ? "this mac" : unique.joined(separator: " · ")
    }

    private func agentSnapshot(_ repo: Repo) -> AgentSnapshot? {
        let checkouts = repo.checkouts ?? []
        let hasLocal = checkouts.isEmpty || checkouts.contains { $0.host.map(MacSelfHost.isThisMac) ?? true }
        // Local agents (this Mac's tmux) win; otherwise a remote agent detected
        // during the status fetch on any of the repo's machines.
        if hasLocal, let local = agents.snapshot(forProjectNamed: repo.name) { return local }
        for c in checkouts {
            if let h = c.host, !MacSelfHost.isThisMac(h),
               let remote = status.remoteAgent(host: h, repoName: repo.name) {
                return remote
            }
        }
        return nil
    }

    private func localAgentActivity(_ repo: Repo) -> AgentActivity {
        agentSnapshot(repo)?.activity ?? .none
    }

    private func projectAgent(_ project: Project) -> AgentActivity {
        let acts = project.sortedRepos.map { localAgentActivity($0) }
        if acts.contains(.waiting) { return .waiting }
        if acts.contains(.running) { return .running }
        if acts.contains(.finished) { return .finished }
        return .none
    }

    private func liveAgents(_ project: Project) -> [RepoRowVM] {
        repoRows(project).filter { $0.agent != .none }
    }

    /// The one-line glance summary across the project's repos.
    private func glance(_ project: Project) -> ProjectGlance {
        let rows = repoRows(project)
        let changes = rows.reduce(0) { $0 + (GitLineFormatter.make($1.git).dirty) }
        let working = rows.filter { $0.agent == .running }.count
        let needs   = rows.filter { $0.agent == .waiting }.count
        return ProjectGlance(changes: changes, working: working, needsYou: needs,
                             repoCount: rows.count, age: shioShortAge(project.lastOpenedAt))
    }
}

/// Display data for one repo row inside the dashboard.
struct RepoRowVM: Identifiable {
    let id: PersistentIdentifier
    let repo: Repo
    let name: String
    let machines: String
    let git: GitProbe?
    let agent: AgentActivity
    var agentName: String? = nil
    var agentDetail: String? = nil
}

/// The aggregate one-liner shown under the project title.
struct ProjectGlance {
    var changes: Int
    var working: Int
    var needsYou: Int
    var repoCount: Int
    var age: String
}

// MARK: - Dashboard

private struct MacProjectDashboard: View {
    @Bindable var project: Project
    let repos: [RepoRowVM]
    let glance: ProjectGlance
    let liveAgents: [RepoRowVM]
    let openRepo: (Repo) -> Void
    let openTerminal: () -> Void
    let addRepo: () -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \Skill.createdAt) private var allSkills: [Skill]
    @State private var renaming = false
    @State private var addingSkill = false
    @State private var editingSkill: Skill?

    private var globalSkills: [Skill] { allSkills.filter { $0.isGlobal && $0.enabled } }
    private var projectSkills: [Skill] {
        allSkills.filter { $0.project?.persistentModelID == project.persistentModelID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
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
    }

    // MARK: header + glance

    private var header: some View {
        HStack(spacing: 11) {
            Text(String(project.name.first ?? "•").uppercased())
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(ShioTheme.accent)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ShioTheme.accentBg))
            if renaming {
                TextField("Project name", text: $project.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .semibold))
                    .onSubmit { try? context.save(); renaming = false }
            } else {
                Text(project.name).font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ShioTheme.textPrimary)
            }
            Text("\(glance.repoCount) repo\(glance.repoCount == 1 ? "" : "s")\(glance.age.isEmpty ? "" : " · \(glance.age)")")
                .font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
            Spacer()
            ShioButton(renaming ? "Done" : "Rename", .secondary, compact: true) {
                if renaming { try? context.save() }
                renaming.toggle()
            }
            ShioButton("Open terminal", .ghost, icon: "terminal", compact: true) { openTerminal() }
                .keyboardShortcut("t", modifiers: .command)
        }
        .padding(.bottom, 12)
    }

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
                ForEach(repos) { row in RepoRowView(row: row, open: { openRepo(row.repo) }) }
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
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(row.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
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
