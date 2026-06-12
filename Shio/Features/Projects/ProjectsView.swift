import SwiftUI
import SwiftData

/// Home tab — the command center, supervision-first. Your projects across every
/// machine as a calm scannable list; the one that needs you floats to the top
/// with its agent's question inline. Tap a project → its dashboard (reordered for
/// mobile: needs-you and agents up top). Built on the terminal-refined kit.
struct ProjectsView: View {

    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @State private var showingSettings = false
    @State private var isAddingProject = false
    @State private var showingTerminal = false
    @State private var selectedProject: Project?
    @State private var noCheckoutName: String?
    private let sessionStore = SessionStore.shared
    private let agents = AgentStateStore.shared
    private let status = ProjectStatusStore.shared

    /// Needs-you first, then running, then most-recently-opened.
    private var sortedProjects: [Project] {
        projects.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (a.lastOpenedAt ?? .distantPast) > (b.lastOpenedAt ?? .distantPast)
        }
    }

    private func rank(_ p: Project) -> Int {
        switch agentActivity(for: p) {
        case .waiting: return 0
        case .running: return 1
        default:       return 2
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedProjects) { project in
                                ProjectListRow(
                                    project: project,
                                    activity: agentActivity(for: project),
                                    agentName: agentSnapshot(for: project)?.agentName,
                                    agentDetail: agentSnapshot(for: project)?.detail,
                                    changes: totalChanges(project),
                                    repoCount: (project.repos ?? []).count,
                                    machines: machinesSummary(project),
                                    open: { selectedProject = project }
                                )
                                .contextMenu {
                                    Button(role: .destructive) { remove(project) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                Rectangle().fill(ShioTheme.line).frame(height: 1)
                            }
                        }
                    }
                    .refreshable {
                        refreshStatus()
                        await SyncRefresh.run(context)
                    }
                }
            }
            .background(ShioTheme.background)
            .shioNavTitle("shio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAddingProject = true } label: {
                        Image(systemName: "plus").foregroundStyle(ShioTheme.textPrimary)
                    }
                    .accessibilityLabel("Add project")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "person.crop.circle").foregroundStyle(ShioTheme.textPrimary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(item: $selectedProject) { proj in
                ProjectOverviewView(project: proj, openRepo: openRepo, openProject: { open(proj) })
            }
            .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
            .sheet(isPresented: $isAddingProject) { AddProjectSheet() }
            .fullScreenCover(isPresented: $showingTerminal) { TerminalScene() }
            .alert("No machine for this project", isPresented: Binding(
                get: { noCheckoutName != nil }, set: { if !$0 { noCheckoutName = nil } })) {
                Button("OK") { noCheckoutName = nil }
            } message: {
                Text("“\(noCheckoutName ?? "")” has no checkout on a reachable machine yet. Add one from the project's dashboard (Repos → Open on), or re-add the machine it lived on.")
            }
            .onAppear { refreshStatus() }
            // Cheap keep-fresh while the list is on screen (mirrors the Mac
            // dashboard timer): needs-you cards appear/clear without a manual
            // pull. warmOnly so it never wakes a sleeping remote.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    if Task.isCancelled { break }
                    status.refresh(ProjectStatusStore.targets(
                        for: projects, isLocalHost: { _ in false }, warmOnly: true))
                }
            }
        }
    }

    // Skills materialize inside SessionStore.openOrCreate — it knows the
    // exact checkout being opened, which this view doesn't.
    private func openRepo(_ repo: Repo) {
        if sessionStore.openOrCreate(repo: repo) != nil {
            showingTerminal = true
        } else {
            // No checkout (or its host is gone) — say so instead of a dead tap.
            noCheckoutName = repo.name
        }
    }

    private func open(_ project: Project) {
        if sessionStore.openOrCreate(project: project) != nil {
            showingTerminal = true
        } else {
            noCheckoutName = project.name
        }
    }

    /// Remove a project from Shio (the repo on the machine is left alone).
    private func remove(_ project: Project) {
        ModelCascade.delete(project: project, context: context, isLocalHost: { _ in false })
        try? context.save()
    }

    // MARK: - Status + agent reads

    private func refreshStatus() {
        let targets = ProjectStatusStore.targets(for: projects, isLocalHost: { _ in false })
        status.refresh(targets)
        status.refreshPRs(targets)
    }

    /// Total uncommitted changes across the project's repos — the list indicator.
    private func totalChanges(_ project: Project) -> Int {
        project.sortedRepos.reduce(0) { sum, repo in
            let probe = repo.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
            return sum + GitLineFormatter.make(probe).dirty
        }
    }

    private func machinesSummary(_ project: Project) -> String {
        let names = project.allCheckouts.compactMap { $0.host?.name }
        var seen = Set<String>(); var unique: [String] = []
        for n in names where !seen.contains(n) { seen.insert(n); unique.append(n) }
        if unique.isEmpty, let legacy = project.host?.name { return legacy }
        return unique.isEmpty ? "no machine" : unique.joined(separator: " · ")
    }

    /// Worst-case agent snapshot across this project's open sessions (waiting
    /// outranks running outranks finished).
    private func agentSnapshot(for project: Project) -> AgentSnapshot? {
        var snaps = sessionStore.sessions(forProject: project.persistentModelID)
            .compactMap { agents.snapshot(for: $0.id) }
        // Also any agent detected on a machine during the status fetch — so a
        // project with an agent working on a remote you aren't viewing still
        // floats up (the supervision-first away case).
        for repo in project.sortedRepos {
            for c in (repo.checkouts ?? []) {
                if let h = c.host, let r = status.remoteAgent(host: h, repoName: repo.name) {
                    snaps.append(r)
                }
            }
        }
        return snaps.first { $0.activity == .waiting }
            ?? snaps.first { $0.activity == .running }
            ?? snaps.first { $0.activity == .finished }
    }

    private func agentActivity(for project: Project) -> AgentActivity {
        agentSnapshot(for: project)?.activity ?? .none
    }

    private var emptyState: some View {
        VStack(spacing: ShioSpace.lg) {
            Text("塩")
                .font(ShioFont.kanji(size: 72))
                .foregroundStyle(ShioTheme.textTertiary)
            Text("No projects yet")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("Add a repo from a machine you've connected, and it lives here. Open it to drop straight into a terminal in that folder.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            ShioButton("Add a project", .primary, icon: "plus") { isAddingProject = true }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioTheme.background)
    }
}

// MARK: - List row

/// One project in the command-center list — mark, name, an inline status line
/// (the agent's question when it needs you), and trailing age + change count.
private struct ProjectListRow: View {
    let project: Project
    let activity: AgentActivity
    let agentName: String?
    let agentDetail: String?
    let changes: Int
    let repoCount: Int
    let machines: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                mark
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ShioTheme.textPrimary)
                    statusLine
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    let age = shioShortAge(project.lastOpenedAt)
                    if !age.isEmpty {
                        Text(age).font(.system(size: 11)).foregroundStyle(ShioTheme.textTertiary)
                            .monospacedDigit()
                    }
                    if changes > 0 {
                        HStack(spacing: 5) {
                            ShioStatusDot(status: .warning, size: 7)
                            Text("\(changes)").font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(ShioTheme.warning)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var mark: some View {
        Group {
            switch activity {
            case .waiting:
                Text("●").font(.system(size: 12)).foregroundStyle(ShioTheme.warning)
            case .running:
                Text(String(project.name.first ?? "•").uppercased())
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShioTheme.accent)
            default:
                Text("◦").font(.system(size: 13)).foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .frame(width: 24, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(activity == .waiting ? ShioTheme.warningBg
                      : (activity == .running ? ShioTheme.accentBg : ShioTheme.hover))
        )
        .padding(.top, 1)
    }

    @ViewBuilder private var statusLine: some View {
        switch activity {
        case .waiting:
            HStack(spacing: 5) {
                Text("⚑").font(.system(size: 12))
                Text(detailText).lineLimit(1).truncationMode(.tail)
            }
            .font(.system(size: 12))
            .foregroundStyle(ShioTheme.warning)
        case .running:
            HStack(spacing: 6) {
                ShioBrailleSpinner(status: .info, size: 11)
                Text("\(agentName ?? "Agent") working\(repoSuffix)")
                    .lineLimit(1).truncationMode(.tail)
            }
            .font(.system(size: 12))
            .foregroundStyle(ShioTheme.info)
        default:
            Text(idleSummary)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private var detailText: String {
        if let d = agentDetail, !d.isEmpty { return "needs you · \"\(d)\"" }
        return "needs you"
    }
    private var repoSuffix: String { repoCount > 1 ? " · \(repoCount) repos" : "" }
    private var idleSummary: String {
        if repoCount > 1 { return "\(repoCount) repos · \(machines)" }
        return machines
    }
}
