import SwiftUI
import SwiftData

/// Home tab — the command center. Your projects across every machine, each card
/// showing its git state and any agent that needs you (those float to the top).
/// Tap a card to drop into its terminal.
struct ProjectsView: View {

    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @State private var showingSettings = false
    @State private var isAddingProject = false
    @State private var showingTerminal = false
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
                        LazyVStack(spacing: ShioSpace.md) {
                            ForEach(sortedProjects) { project in
                                ProjectCard(
                                    project: project,
                                    agent: agentActivity(for: project),
                                    agentName: agentSnapshot(for: project)?.agentName,
                                    agentDetail: agentSnapshot(for: project)?.detail,
                                    git: gitProbe(for: project),
                                    open: { open(project) },
                                    remove: { remove(project) }
                                )
                            }
                        }
                        .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
                        .padding(.vertical, ShioSpace.md)
                    }
                    .refreshable {
                        refreshStatus()
                        await SyncRefresh.run(context)
                    }
                }
            }
            .background(ShioColor.Chrome.background)
            .shioNavTitle("shio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAddingProject = true } label: {
                        Image(systemName: "plus").foregroundStyle(ShioColor.Text.primary)
                    }
                    .accessibilityLabel("Add project")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "person.crop.circle").foregroundStyle(ShioColor.Text.primary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
            .sheet(isPresented: $isAddingProject) { AddProjectSheet() }
            .fullScreenCover(isPresented: $showingTerminal) { TerminalScene() }
            .onAppear { refreshStatus() }
        }
    }

    private func open(_ project: Project) {
        if sessionStore.openOrCreate(project: project) != nil {
            showingTerminal = true
        }
    }

    /// Remove a project from Shio (the repo on the machine is left alone).
    private func remove(_ project: Project) {
        context.delete(project)
        try? context.save()
    }

    // MARK: - Status + agent reads

    /// Kick a git-status refresh for every visible checkout. On iOS every host is
    /// remote (no local machine), so isLocalHost is always false.
    private func refreshStatus() {
        status.refresh(ProjectStatusStore.targets(for: projects, isLocalHost: { _ in false }))
    }

    private func gitProbe(for project: Project) -> GitProbe? {
        guard let c = project.activeCheckout else { return nil }
        return status.status(forHost: c.host, path: c.path)?.probe
    }

    /// Worst-case agent snapshot across this project's open sessions (waiting
    /// outranks running outranks finished).
    private func agentSnapshot(for project: Project) -> AgentSnapshot? {
        let snaps = sessionStore.sessions(forProject: project.persistentModelID)
            .compactMap { agents.snapshot(for: $0.id) }
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
                .foregroundStyle(ShioColor.Text.primary)
            Text("No projects yet")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)
            Text("Add a repo from a machine you've connected, and it lives here. Open it to drop straight into a terminal in that folder.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioColor.Text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            ShioButton("Add a project") { isAddingProject = true }
                .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioColor.Chrome.background)
    }
}

// MARK: - Card

private struct ProjectCard: View {
    let project: Project
    let agent: AgentActivity
    let agentName: String?
    let agentDetail: String?
    let git: GitProbe?
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                // Needs-you accent — a quiet bar, not a glow.
                Rectangle()
                    .fill(agent == .waiting ? ShioColor.State.warning : Color.clear)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: ShioSpace.sm) {
                    header
                    machinesLine
                    gitLine
                    if let agentText { agentLine(agentText) }
                }
                .padding(ShioSpace.md)
            }
            .background(ShioColor.Chrome.surface)
            .clipShape(RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShioRadius.lg, style: .continuous)
                    .strokeBorder(ShioColor.Chrome.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: remove) { Label("Remove", systemImage: "trash") }
        }
    }

    private var header: some View {
        HStack(spacing: ShioSpace.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(ShioColor.Text.secondary)
            Text(project.name)
                .font(ShioFont.bodyEmphasis)
                .foregroundStyle(ShioColor.Text.primary)
            Spacer()
            let age = shioShortAge(project.lastOpenedAt)
            if !age.isEmpty {
                Text(age)
                    .font(ShioFont.footnote)
                    .foregroundStyle(ShioColor.Text.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private var machines: [String] {
        let names = (project.checkouts ?? []).compactMap { $0.host?.name }
        var seen = Set<String>(); var unique: [String] = []
        for n in names where !seen.contains(n) { seen.insert(n); unique.append(n) }
        if unique.isEmpty, let legacy = project.host?.name { return [legacy] }
        return unique
    }

    private var machinesLine: some View {
        Text(machines.isEmpty ? "no machine" : machines.joined(separator: " · "))
            .font(ShioFont.Mono.inline)
            .foregroundStyle(ShioColor.Text.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private var gitLine: some View {
        let m = GitLineFormatter.make(git)
        HStack(spacing: ShioSpace.sm) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                Text(m.branch).lineLimit(1).truncationMode(.middle)
            }
            .font(ShioFont.Mono.inline)
            .foregroundStyle(branchColor(m.state))

            if m.hasTracking {
                if m.ahead > 0 { chip("↑\(m.ahead)", ShioColor.Text.secondary) }
                if m.behind > 0 { chip("↓\(m.behind)", ShioColor.Text.secondary) }
                if m.dirty > 0 {
                    chip("●\(m.dirty)", ShioColor.State.warning)
                } else {
                    chip("clean", ShioColor.State.success)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(ShioFont.footnote)
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private func branchColor(_ state: GitLineModel.State) -> Color {
        switch state {
        case .loading, .unreachable: return ShioColor.Text.tertiary
        default: return ShioColor.Text.secondary
        }
    }

    private var agentText: String? {
        switch agent {
        case .waiting:  return agentDetail ?? "needs you"
        case .running:  return "\(agentName ?? "Agent") · working…"
        case .finished: return "\(agentName ?? "Agent") · finished"
        case .none:     return nil
        }
    }

    @ViewBuilder
    private func agentLine(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: agent == .waiting ? "bell.badge.fill"
                  : (agent == .finished ? "checkmark.circle" : "circle.fill"))
                .font(.system(size: agent == .running ? 7 : 11))
            Text(text).lineLimit(1)
        }
        .font(ShioFont.footnote)
        .foregroundStyle(agent == .waiting ? ShioColor.State.warning
                         : (agent == .finished ? ShioColor.State.success : ShioColor.Text.tertiary))
    }
}
