import SwiftUI
import SwiftData

/// The project dashboard on iPhone — supervision-first, reordered for mobile:
/// a one-line glance, then **needs-you** and **agents** up top (the away
/// use-case), repos next, and the grounding/config modules as tap-in rows.
/// Built on the terminal-refined kit. Live now: repos (git) + agents (from open
/// sessions). Approve/deny on a needs-you card arrives with remote control (P6);
/// for now the card jumps you into the terminal to answer.
struct ProjectOverviewView: View {
    @Bindable var project: Project
    let openRepo: (Repo) -> Void
    let openProject: () -> Void
    @Environment(\.modelContext) private var context
    private let status = ProjectStatusStore.shared
    private let sessionStore = SessionStore.shared
    private let agents = AgentStateStore.shared

    @Query(sort: \Skill.createdAt) private var allSkills: [Skill]
    @State private var showingAddRepo = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingNotes = false
    @State private var commitCtx: CommitContext?

    struct CommitContext: Identifiable { let id = UUID(); let repo: Repo }

    private var skillsCount: Int {
        allSkills.filter { ($0.isGlobal && $0.enabled)
            || $0.project?.persistentModelID == project.persistentModelID }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                glanceBar
                if !needsYou.isEmpty {
                    sectionHeader("needs you")
                    ForEach(needsYou) { item in needsYouCard(item) }
                }
                if !working.isEmpty {
                    sectionHeader("agents")
                    ForEach(working) { item in agentRow(item) }
                }
                sectionHeader("repos", add: { showingAddRepo = true })
                ForEach(project.sortedRepos) { repo in repoRow(repo) }

                sectionHeader("grounding")
                NavigationLink {
                    SkillsLibraryView()
                } label: {
                    moduleRow(icon: "wrench.and.screwdriver", name: "Skills",
                              detail: skillsCount == 0 ? "none" : "\(skillsCount) active", chevron: true)
                }.buttonStyle(.plain)
                Button { showingNotes = true } label: {
                    moduleRow(icon: "doc.text", name: "Memory & context",
                              detail: (project.notes?.isEmpty == false) ? "notes" : "empty", chevron: true)
                }.buttonStyle(.plain)
                moduleRow(icon: "circle.lefthalf.filled", name: "Integrations", detail: "soon")
            }
            .padding(.vertical, ShioSpace.sm)
        }
        .background(ShioTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(String(project.name.first ?? "•").uppercased())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShioTheme.accent)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ShioTheme.accentBg))
                    Text(project.name).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ShioTheme.textPrimary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { openProject() } label: {
                    Image(systemName: "terminal").foregroundStyle(ShioTheme.accent)
                }
                .accessibilityLabel("Open terminal")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = project.name; showingRename = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button { showingAddRepo = true } label: {
                        Label("Add repo", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(ShioTheme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showingAddRepo) { AddProjectSheet(targetProject: project) }
        .sheet(isPresented: $showingNotes) { notesSheet }
        .sheet(item: $commitCtx) { ctx in
            let c = ctx.repo.activeCheckout
            let probe = c.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
            let config: SSHClient.Configuration? = c?.host.map { h in
                SSHClient.Configuration(host: h.hostname, port: h.port, username: h.username,
                                        authentication: .systemKeys, initialCols: 80, initialRows: 24)
            }
            CommitSheet(repoName: ctx.repo.name, dirtyCount: GitLineFormatter.make(probe).dirty,
                        path: c?.path ?? "", config: config)
                .presentationDetents([.medium])
        }
        .alert("Rename project", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let n = renameText.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { project.name = n; try? context.save() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            let targets = ProjectStatusStore.targets(for: [project], isLocalHost: { _ in false })
            status.refresh(targets)
            status.refreshPRs(targets)
        }
        // Keep the dashboard live while it's on screen — an in-app Approve
        // clears the needs-you card on the next tick instead of never.
        // warmOnly so it can't wake a sleeping remote.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                status.refresh(ProjectStatusStore.targets(
                    for: [project], isLocalHost: { _ in false }, warmOnly: true))
            }
        }
    }

    // MARK: - Agent reads

    /// A supervised agent for this project — from an open in-app session, or
    /// detected on a machine during the status fetch. Dedup keeps one per label.
    struct AgentItem: Identifiable {
        let id: String; let title: String; let snap: AgentSnapshot
        /// The Mac tmux session to answer (`shio-<repo>`), when derivable — lets
        /// the card approve/deny over iCloud. nil for the phone's own open
        /// sessions (just open the terminal).
        var sessionTmux: String? = nil
    }

    private var agentItems: [AgentItem] {
        var items: [AgentItem] = []
        var seen = Set<String>()
        for s in sessionStore.sessions(forProject: project.persistentModelID) {
            if let snap = agents.snapshot(for: s.id) {
                let title = "\(snap.agentName ?? "Agent") · \(s.displayName)"
                if seen.insert(title).inserted { items.append(.init(id: s.id.uuidString, title: title, snap: snap)) }
            }
        }
        for repo in project.sortedRepos {
            for c in (repo.checkouts ?? []) {
                guard let h = c.host, let snap = status.remoteAgent(host: h, repoName: repo.name) else { continue }
                let title = "\(snap.agentName ?? "Agent") · \(repo.name)"
                if seen.insert(title).inserted {
                    items.append(.init(id: "remote-\(repo.name)", title: title, snap: snap,
                                       sessionTmux: "shio-\(TmuxResume.scrubName(repo.name))"))
                }
            }
        }
        return items
    }
    private var needsYou: [AgentItem] { agentItems.filter { $0.snap.activity == .waiting } }
    private var working:  [AgentItem] { agentItems.filter { $0.snap.activity == .running } }

    /// Answer a blocked agent over iCloud (#33) — the Mac watcher injects the
    /// keystroke. The card clears itself on the next status refresh.
    private func answer(_ sessionTmux: String, _ key: String) {
        Task { await CloudKitSignalService.shared.sendAction(sessionId: sessionTmux, key: key) }
    }

    // MARK: - Glance

    private var glanceBar: some View {
        let changes = project.sortedRepos.reduce(0) { sum, repo in
            let probe = repo.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
            return sum + GitLineFormatter.make(probe).dirty
        }
        let repoCount = project.sortedRepos.count
        return HStack(spacing: 14) {
            if changes > 0 {
                HStack(spacing: 6) { ShioStatusDot(status: .warning, size: 7)
                    Text("\(changes) changes").foregroundStyle(ShioTheme.warning) }
            }
            if !working.isEmpty {
                HStack(spacing: 6) { ShioBrailleSpinner(status: .info, size: 11)
                    Text("working").foregroundStyle(ShioTheme.info) }
            }
            if !needsYou.isEmpty {
                Text("⚑ \(needsYou.count) needs you").foregroundStyle(ShioTheme.warning)
            }
            if changes == 0 && working.isEmpty && needsYou.isEmpty {
                Text("all quiet").foregroundStyle(ShioTheme.textTertiary)
            }
            Spacer(minLength: 0)
            Text("\(repoCount) repo\(repoCount == 1 ? "" : "s")").foregroundStyle(ShioTheme.textTertiary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String, add: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title).font(ShioKitFont.label).tracking(1.5).textCase(.uppercase)
                .foregroundStyle(ShioTheme.textTertiary)
            Spacer()
            if let add {
                Button { add() } label: { Image(systemName: "plus").font(.system(size: 13)) }
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 7)
    }

    private func needsYouCard(_ item: AgentItem) -> some View {
        let snap = item.snap
        return VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
            if let d = snap.detail, !d.isEmpty {
                Text("\"\(d)\"").font(.system(size: 13)).foregroundStyle(ShioTheme.warning)
                    .padding(.top, 6).padding(.bottom, 11)
            } else { Color.clear.frame(height: 11) }
            if let tmux = item.sessionTmux {
                HStack(spacing: 8) {
                    ShioButton("Approve", .primary, icon: "checkmark") { answer(tmux, "y") }
                    ShioButton("Deny", .secondary, icon: "xmark") { answer(tmux, "n") }
                    ShioButton("Open", .ghost, icon: "terminal") { openProject() }
                }
            } else {
                ShioButton("Open terminal to answer", .secondary, icon: "terminal") { openProject() }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(ShioTheme.warningBg))
        .overlay(alignment: .leading) { Rectangle().fill(ShioTheme.warning).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private func agentRow(_ item: AgentItem) -> some View {
        let snap = item.snap
        return Button { openProject() } label: {
            HStack(spacing: 11) {
                ShioBrailleSpinner(status: .info, size: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14)).foregroundStyle(ShioTheme.textPrimary)
                    if let d = snap.detail, !d.isEmpty {
                        Text(d).font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary).lineLimit(1)
                    }
                }
                Spacer()
                Text("jump ›").font(.system(size: 13)).foregroundStyle(ShioTheme.textSecondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
    }

    private func repoRow(_ repo: Repo) -> some View {
        Button { openRepo(repo) } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.name).font(.system(size: 14)).foregroundStyle(ShioTheme.textPrimary)
                    gitLine(repo)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
        .contextMenu {
            let checkouts = repo.checkouts ?? []
            if checkouts.count > 1 {
                Menu("Open on") {
                    ForEach(checkouts, id: \.persistentModelID) { c in
                        Button(c.host?.name ?? "Unknown") {
                            c.lastOpenedAt = .now; try? context.save(); openRepo(repo)
                        }
                    }
                }
            }
            let dirty = repo.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
            if GitLineFormatter.make(dirty).dirty > 0 {
                Button("Commit & push…", systemImage: "arrow.up") { commitCtx = CommitContext(repo: repo) }
            }
        }
    }

    @ViewBuilder private func gitLine(_ repo: Repo) -> some View {
        let probe = repo.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
        let m = GitLineFormatter.make(probe)
        let pr = repo.activeCheckout.flatMap { c in
            status.prList(forHost: c.host, path: c.path).first(where: { $0.state == "OPEN" })
        }
        HStack(spacing: 9) {
            HStack(spacing: 5) {
                Text("⎇").foregroundStyle(ShioTheme.textTertiary)
                Text(m.branch).lineLimit(1).truncationMode(.middle)
            }
            .foregroundStyle(m.state == .loading || m.state == .unreachable ? ShioTheme.textTertiary : ShioTheme.textSecondary)
            if m.hasTracking {
                if m.ahead > 0 { Text("↑\(m.ahead)").foregroundStyle(ShioTheme.textSecondary) }
                if m.behind > 0 { Text("↓\(m.behind)").foregroundStyle(ShioTheme.textSecondary) }
                if m.dirty > 0 {
                    HStack(spacing: 5) { ShioStatusDot(status: .warning, size: 6)
                        Text("\(m.dirty)").foregroundStyle(ShioTheme.warning) }
                } else {
                    Text("✓").foregroundStyle(ShioTheme.success)
                }
            }
            if let pr {
                Text("PR #\(pr.number)").foregroundStyle(pr.isDraft ? ShioTheme.textTertiary : ShioTheme.info)
            }
        }
        .font(.system(size: 12, design: .monospaced)).monospacedDigit()
    }

    private func moduleRow(icon: String, name: String, detail: String, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(ShioTheme.textSecondary).frame(width: 18)
            Text(name).font(.system(size: 14)).foregroundStyle(ShioTheme.textPrimary)
            Spacer()
            Text(detail).font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
    }

    private var notesSheet: some View {
        NavigationStack {
            TextEditor(text: Binding(
                get: { project.notes ?? "" },
                set: { project.notes = $0; try? context.save() }))
                .font(ShioFont.Mono.inline)
                .foregroundStyle(ShioTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(ShioSpace.md)
                .background(ShioTheme.background)
                .navigationTitle("Memory & context")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
