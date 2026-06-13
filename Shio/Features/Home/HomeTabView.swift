import SwiftUI
import SwiftData

/// Home — the command center: an OVERVIEW of every project across every
/// machine, supervision-first (the one that needs you floats to the top with
/// its agent's question inline). You land here, not inside a project; tap one
/// to drop into its dashboard. Titled ~/shio — your root.
struct HomeTabView: View {

    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @State private var showingSettings = false
    @State private var isAddingProject = false
    @State private var selectedProject: Project?
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
                        LazyVStack(spacing: 12) {
                            ForEach(sortedProjects) { project in
                                ProjectOverviewCard(
                                    project: project,
                                    activity: agentActivity(for: project),
                                    agentName: agentSnapshot(for: project)?.agentName,
                                    agentDetail: agentSnapshot(for: project)?.detail,
                                    changes: totalChanges(project),
                                    repoCount: project.sortedRepos.count,
                                    machines: machinesSummary(project),
                                    peek: channelPeek(project),
                                    open: { selectedProject = project }
                                )
                                .contextMenu {
                                    Button(role: .destructive) { remove(project) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
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
                        Image(systemName: "gearshape").foregroundStyle(ShioTheme.textPrimary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(item: $selectedProject) { proj in
                ProjectView(project: proj)
            }
            .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
            .sheet(isPresented: $isAddingProject) { AddProjectSheet() }
            .onAppear { refreshStatus() }
            // Cheap keep-fresh while the overview is on screen: needs-you cards
            // appear/clear without a manual pull. warmOnly so it never wakes a
            // sleeping remote.
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

    /// One entry per repo whose conversation is live — the card's status peek.
    /// Empty when nothing's running (the card shows the quiet summary instead).
    private func channelPeek(_ project: Project) -> [ChannelPeek] {
        project.sortedRepos.compactMap { repo in
            guard let p = ActivityFeed.presence(for: repo), p.snap.activity != .none else { return nil }
            return ChannelPeek(name: repo.name, activity: p.snap.activity)
        }
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

// MARK: - Overview card

/// One repo's live presence, shown in a card's peek row.
struct ChannelPeek: Identifiable {
    let name: String
    let activity: AgentActivity
    var id: String { name }
}

/// One project in the overview — an outline card (warn-tinted when it needs
/// you) with the loudest status line and, when agents are live, a peek of
/// which conversations are running. Echoes the Mac dashboard's bento.
private struct ProjectOverviewCard: View {
    let project: Project
    let activity: AgentActivity
    let agentName: String?
    let agentDetail: String?
    let changes: Int
    let repoCount: Int
    let machines: String
    let peek: [ChannelPeek]
    let open: () -> Void

    private var needsYou: Bool { activity == .waiting }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                top
                statusLine.padding(.leading, 37).padding(.top, 8)
                if !peek.isEmpty { peekRow.padding(.leading, 37).padding(.top, 9) }
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 11, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(needsYou ? ShioTheme.warningBg : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(needsYou ? ShioTheme.warning.opacity(0.4) : ShioTheme.line2, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }

    private var top: some View {
        HStack(spacing: 11) {
            mark
            Text(project.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            let age = shioShortAge(project.lastOpenedAt)
            if !age.isEmpty {
                Text(age).font(.system(size: 11)).foregroundStyle(ShioTheme.textTertiary).monospacedDigit()
            }
            if changes > 0 {
                HStack(spacing: 4) {
                    ShioStatusDot(status: .warning, size: 6)
                    Text("\(changes)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(ShioTheme.warning)
                }
                .padding(.leading, 4)
            }
        }
    }

    private var mark: some View {
        Text(needsYou ? "●" : String(project.name.first ?? "•").uppercased())
            .font(.system(size: needsYou ? 12 : 12, weight: .medium, design: .monospaced))
            .foregroundStyle(needsYou ? ShioTheme.warning : (activity == .running ? ShioTheme.accent : ShioTheme.textTertiary))
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(needsYou ? .clear : (activity == .running ? ShioTheme.accentBg : ShioTheme.hover))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(needsYou ? ShioTheme.warning.opacity(0.4) : .clear, lineWidth: 1)
            )
    }

    @ViewBuilder private var statusLine: some View {
        switch activity {
        case .waiting:
            HStack(spacing: 5) {
                Text("⚑").font(.system(size: 12))
                Text(detailText).lineLimit(1).truncationMode(.tail)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(ShioTheme.warning)
        case .running:
            HStack(spacing: 6) {
                ShioBrailleSpinner(status: .info, size: 11)
                Text("\(agentName ?? "Agent") working\(detailSuffix)")
                    .lineLimit(1).truncationMode(.tail)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(ShioTheme.info)
        default:
            Text(idleSummary)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private var peekRow: some View {
        HStack(spacing: 14) {
            ForEach(peek.prefix(4)) { ch in
                HStack(spacing: 5) {
                    presenceGlyph(ch.activity)
                    Text(ch.name).foregroundStyle(ShioTheme.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5))
    }

    @ViewBuilder private func presenceGlyph(_ a: AgentActivity) -> some View {
        switch a {
        case .waiting:  Text("⚑").font(.system(size: 11)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
        case .running:  ShioBrailleSpinner(status: .info, size: 10)
        case .finished: Text("✓").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ShioTheme.success)
        case .none:     Text("⎇").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
        }
    }

    private var detailText: String {
        if let d = agentDetail, !d.isEmpty { return "\(agentName ?? "Agent") needs you · \"\(d)\"" }
        return "\(agentName ?? "An agent") needs you"
    }
    private var detailSuffix: String {
        if let d = agentDetail, !d.isEmpty { return " · \(d)" }
        return ""
    }
    private var idleSummary: String {
        let n = repoCount
        return "\(n) repo\(n == 1 ? "" : "s") · \(machines) · all quiet"
    }
}
