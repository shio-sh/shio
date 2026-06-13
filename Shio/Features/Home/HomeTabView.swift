import SwiftUI
import SwiftData

/// 塩 Home — this team's conversations. The switcher sits in the header
/// (tap the name → the team's dashboard; ▾ switches teams), a glance line
/// under it, then AGENTS (live presence), SHELLS (your machines' loose
/// terminals) and REPOS (each repo's standing conversation).
struct HomeTabView: View {
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Host.name) private var hosts: [Host]
    @Environment(\.modelContext) private var context
    @AppStorage("shio.ios.project") private var selectedName: String = ""
    @State private var isAddingProject = false
    @State private var showingTerminal = false
    @State private var showingSettings = false
    @State private var dashboardProject: Project?
    @State private var noCheckoutName: String?
    private let status = ProjectStatusStore.shared
    private let sessionStore = SessionStore.shared

    private var selected: Project? {
        projects.first { $0.name == selectedName } ?? projects.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else if let project = selected {
                    home(project)
                }
            }
            .background(ShioTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $dashboardProject) { project in
                ProjectOverviewView(project: project,
                                    openRepo: openRepo,
                                    openProject: { open(project) })
            }
        }
        .sheet(isPresented: $isAddingProject) { AddProjectSheet() }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        .fullScreenCover(isPresented: $showingTerminal) { TerminalScene() }
        .alert("No machine for this repo", isPresented: Binding(
            get: { noCheckoutName != nil }, set: { if !$0 { noCheckoutName = nil } })) {
            Button("OK") { noCheckoutName = nil }
        } message: {
            Text("“\(noCheckoutName ?? "")” has no checkout on a reachable machine yet. Add one from the dashboard (Repos → Open on), or re-add the machine it lived on.")
        }
        .onAppear { refreshStatus() }
        // Cheap keep-fresh while Home is on screen — needs-you rows
        // appear/clear without a manual pull. warmOnly so it never wakes
        // a sleeping remote.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                status.refresh(ProjectStatusStore.targets(
                    for: projects, isLocalHost: { _ in false }, warmOnly: true))
            }
        }
    }

    // MARK: the team's home

    private func home(_ project: Project) -> some View {
        let items = project.sortedRepos.compactMap { repo -> ActivityItem? in
            guard let p = ActivityFeed.presence(for: repo) else { return nil }
            return ActivityItem(id: repo.name, activity: p.snap.activity,
                                agentName: p.snap.agentName ?? "Agent",
                                detail: p.snap.detail, repoName: repo.name,
                                projectName: project.name, age: shioShortAge(p.at),
                                repo: repo, sessionID: p.sessionID)
        }
        return VStack(spacing: 0) {
            header(project)
            glanceLine(project, items: items)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Empty-states law: AGENTS only exists while presence is live.
                    if !items.isEmpty {
                        sectionHeader("agents")
                        ForEach(items) { agentRow($0) }
                    }
                    if !dedupedHosts.isEmpty {
                        sectionHeader("shells")
                        ForEach(dedupedHosts) { shellRow($0) }
                    }
                    sectionHeader("repos")
                    if project.sortedRepos.isEmpty {
                        quietHint("No repos yet — add one from the dashboard.")
                    } else {
                        ForEach(project.sortedRepos) { repoRow($0) }
                    }
                }
                .padding(.bottom, 12)
            }
            .refreshable {
                refreshStatus()
                await SyncRefresh.run(context)
            }
        }
    }

    private func header(_ project: Project) -> some View {
        HStack(spacing: 9) {
            Button { dashboardProject = project } label: {
                HStack(spacing: 9) {
                    Text(String(project.name.first ?? "•").uppercased())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShioTheme.accent)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ShioTheme.accentBg))
                    Text(project.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(ShioTheme.textPrimary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(project.name)'s dashboard")

            Menu {
                ForEach(projects) { p in
                    Button {
                        select(p)
                    } label: {
                        if p.persistentModelID == project.persistentModelID {
                            Label(p.name, systemImage: "checkmark")
                        } else {
                            Text(p.name)
                        }
                    }
                }
                Divider()
                Button { isAddingProject = true } label: {
                    Label("New project…", systemImage: "plus")
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Switch project")

            Spacer()

            Button { isAddingProject = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ShioTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add project")

            settingsButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// The one Settings entry point (Settings left More with it) — on Home,
    /// the "you" anchor.
    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ShioTheme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private func glanceLine(_ project: Project, items: [ActivityItem]) -> some View {
        let changes = project.sortedRepos.reduce(0) { $0 + dirtyCount($1) }
        let working = items.filter { $0.activity == .running }.count
        let needs = items.filter { $0.activity == .waiting }.count
        return Group {
            if changes > 0 || working > 0 || needs > 0 {
                HStack(spacing: 12) {
                    if changes > 0 {
                        HStack(spacing: 5) {
                            ShioStatusDot(status: .warning)
                            Text("\(changes) changes").foregroundStyle(ShioTheme.warning)
                        }
                    }
                    if working > 0 {
                        HStack(spacing: 5) {
                            ShioBrailleSpinner(status: .info, size: 10)
                            Text("\(working) working").foregroundStyle(ShioTheme.info)
                        }
                    }
                    if needs > 0 {
                        Text("⚑ \(needs) needs you")
                            .foregroundStyle(ShioTheme.warning)
                            .shioNeedsPulse()
                    }
                    Spacer()
                }
                .font(.system(size: 11.5, design: .monospaced))
                .monospacedDigit()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    // MARK: rows

    private func agentRow(_ item: ActivityItem) -> some View {
        Button { jump(item) } label: {
            HStack(spacing: 10) {
                Group {
                    switch item.activity {
                    case .waiting:
                        Text("⚑").font(.system(size: 12)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
                    case .running:
                        ShioBrailleSpinner(status: .info, size: 12)
                    default:
                        Text("✓").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.success)
                    }
                }
                .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.agentName) · \(item.repoName)")
                        .font(.system(size: 14))
                        .foregroundStyle(ShioTheme.textPrimary)
                        .lineLimit(1)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(item.activity == .waiting ? "\u{201C}\(detail)\u{201D}" : detail)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(item.activity == .waiting ? ShioTheme.warning : ShioTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if item.activity == .waiting {
                    Text("needs you")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ShioTheme.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(Capsule().strokeBorder(ShioTheme.warning.opacity(0.4), lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shellRow(_ host: Host) -> some View {
        Button {
            sessionStore.openOrCreate(host: host)
            showingTerminal = true
        } label: {
            HStack(spacing: 10) {
                Text("%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .frame(width: 14)
                Text(host.name)
                    .font(.system(size: 14))
                    .foregroundStyle(ShioTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !sessionStore.sessions(for: host.persistentModelID).isEmpty {
                    Text("live")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func repoRow(_ repo: Repo) -> some View {
        Button { openRepo(repo) } label: {
            HStack(spacing: 10) {
                Text("⎇")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .frame(width: 14)
                Text(repo.name)
                    .font(.system(size: 14))
                    .foregroundStyle(ShioTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    let dirty = dirtyCount(repo)
                    if dirty > 0 {
                        Text("\(dirty)").foregroundStyle(ShioTheme.warning)
                    }
                    if let pr = openPR(repo) {
                        if dirty > 0 { Text("·").foregroundStyle(ShioTheme.textTertiary) }
                        Text("PR #\(pr.number)").foregroundStyle(ShioTheme.textTertiary)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(2)
            .foregroundStyle(ShioTheme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func quietHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(ShioTheme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    // MARK: data + actions

    private var dedupedHosts: [Host] { hosts.dedupedByIdentity }

    private func select(_ project: Project) {
        selectedName = project.name
        project.lastOpenedAt = .now
        try? context.save()
    }

    private func jump(_ item: ActivityItem) {
        if sessionStore.openOrCreate(repo: item.repo) != nil {
            showingTerminal = true
        } else {
            noCheckoutName = item.repoName
        }
    }

    // Skills materialize inside SessionStore.openOrCreate — it knows the
    // exact checkout being opened, which this view doesn't.
    private func openRepo(_ repo: Repo) {
        if sessionStore.openOrCreate(repo: repo) != nil {
            showingTerminal = true
        } else {
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

    private func refreshStatus() {
        let targets = ProjectStatusStore.targets(for: projects, isLocalHost: { _ in false })
        status.refresh(targets)
        status.refreshPRs(targets)
    }

    private func dirtyCount(_ repo: Repo) -> Int {
        guard let c = repo.activeCheckout else { return 0 }
        return GitLineFormatter.make(status.status(forHost: c.host, path: c.path)?.probe).dirty
    }

    private func openPR(_ repo: Repo) -> PullRequest? {
        guard let c = repo.activeCheckout else { return nil }
        return status.prList(forHost: c.host, path: c.path).first { $0.state == "OPEN" }
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
        // Settings stays reachable even before the first project exists.
        .overlay(alignment: .topTrailing) {
            settingsButton.padding(.horizontal, 16).padding(.top, 8)
        }
    }
}
