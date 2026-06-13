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
                                    changes: totalChanges(project),
                                    isMostRecent: project.persistentModelID == projects.first?.persistentModelID,
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
            // A faint 塩 fills the void below the cards (behind content, so a
            // long list simply covers it) — warmth, not noise.
            .background(alignment: .bottom) {
                Text("塩")
                    .font(.system(size: 84))
                    .foregroundStyle(ShioTheme.textPrimary)
                    .opacity(0.04)
                    .padding(.bottom, 28)
                    .allowsHitTesting(false)
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


// MARK: - Overview card (A resting · B active)

/// One project in the overview. At rest it's a calm whisper card — the
/// identity-tinted mark, the name, and one faint terminal line (the project's
/// git state); the most-recent project carries a live blinking cursor. The
/// moment an agent is live it expands into a hero: the repos inline with
/// presence, plus a needs-you bar you can answer in place. (His call: A
/// resting + B active.)
private struct ProjectOverviewCard: View {
    let project: Project
    let activity: AgentActivity
    let changes: Int
    let isMostRecent: Bool
    let open: () -> Void
    private let status = ProjectStatusStore.shared

    private var needsYou: Bool { activity == .waiting }
    private var isLive: Bool { activity == .running || activity == .waiting }
    private var waitingItem: ActivityItem? {
        ActivityFeed.items(projects: [project]).first { $0.activity == .waiting }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 13)
            if isLive {
                if let item = waitingItem {
                    needbar(item).padding(.horizontal, 14).padding(.top, 10)
                }
                Rectangle().fill(ShioTheme.line).frame(height: 1).padding(.top, 11)
                ForEach(project.sortedRepos) { repo in heroRepoRow(repo) }
                foot.padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 12)
            } else {
                whisper.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(needsYou ? ShioTheme.warningBg.opacity(0.5) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(needsYou ? ShioTheme.warning.opacity(0.4) : ShioTheme.line2, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .padding(.horizontal, 14)
    }

    // MARK: header (shared)

    private var header: some View {
        HStack(spacing: 12) {
            mark
            Text(project.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            let age = shioShortAge(project.lastOpenedAt)
            if !age.isEmpty {
                Text(age).font(.system(size: 11.5)).foregroundStyle(ShioTheme.textTertiary).monospacedDigit()
            }
            if changes > 0 {
                HStack(spacing: 4) {
                    ShioStatusDot(status: .warning, size: 6)
                    Text("\(changes)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(ShioTheme.warning)
                }
                .padding(.leading, 7)
            }
        }
    }

    private var mark: some View {
        let tint = ProjectIdentity.color(for: project.name)
        return Text(String(project.name.first ?? "•").uppercased())
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ProjectIdentity.wash(for: project.name)))
    }

    // MARK: resting whisper (A)

    private var whisper: some View {
        HStack(spacing: 0) {
            Text(whisperText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1).truncationMode(.middle)
            if isMostRecent { ShioCardCursor() }
        }
        .padding(.leading, 42)
    }

    private var whisperText: String {
        let repo = project.sortedRepos.first
        let probe = repo?.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
        let m = GitLineFormatter.make(probe)
        if project.sortedRepos.isEmpty { return "⎇ no repos yet" }
        if changes > 0 { return "⎇ \(m.branch) · \(changes) uncommitted" }
        if m.hasTracking { return "⎇ \(m.branch) · clean" }
        return "⎇ \(m.branch)"
    }

    // MARK: active hero (B)

    private func needbar(_ item: ActivityItem) -> some View {
        HStack(spacing: 8) {
            Text("⚑").font(.system(size: 12)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
            Text(item.detail.map { "\(item.agentName) · \"\($0)\"" } ?? "\(item.agentName) needs you")
                .font(.system(size: 11.5)).foregroundStyle(ShioTheme.warning).lineLimit(1)
            Spacer(minLength: 6)
            ShioMiniButton(title: "Approve", status: .success) { Haptics.medium(); ActivityFeed.reply(item, key: "y") }
            ShioMiniButton(title: "Deny", status: .danger) { Haptics.medium(); ActivityFeed.reply(item, key: "n") }
        }
        .padding(.vertical, 9).padding(.horizontal, 11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ShioTheme.warningBg))
        .overlay(alignment: .leading) { Rectangle().fill(ShioTheme.warning).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func heroRepoRow(_ repo: Repo) -> some View {
        let presence = ActivityFeed.presence(for: repo)
        let act = presence?.snap.activity ?? .none
        let m = GitLineFormatter.make(gitProbe(repo))
        let pr = repo.activeCheckout.flatMap { c in
            status.prList(forHost: c.host, path: c.path).first { $0.state == "OPEN" }
        }
        return HStack(spacing: 10) {
            presenceGlyph(act).frame(width: 14)
            Text(repo.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
            Group {
                switch act {
                case .running: Text(presence?.snap.detail ?? "working").foregroundStyle(ShioTheme.info)
                case .waiting: Text("waiting on you").foregroundStyle(ShioTheme.warning)
                default:       Text(m.branch).foregroundStyle(ShioTheme.textTertiary)
                }
            }
            .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                if m.dirty > 0 {
                    HStack(spacing: 3) { ShioStatusDot(status: .warning, size: 5); Text("\(m.dirty)").foregroundStyle(ShioTheme.warning) }
                } else if m.hasTracking {
                    Text("✓").foregroundStyle(ShioTheme.success)
                }
                if let pr { Text("PR #\(pr.number)").foregroundStyle(ShioTheme.textTertiary) }
            }
            .font(.system(size: 10.5, design: .monospaced)).monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var foot: some View {
        HStack(spacing: 7) {
            Image(systemName: "desktopcomputer").font(.system(size: 10)).foregroundStyle(ShioTheme.textTertiary)
            let n = project.sortedRepos.count
            Text("\(machinesText) · \(n) repo\(n == 1 ? "" : "s")")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private var machinesText: String {
        let names = project.allCheckouts.compactMap { $0.host?.name }
        var seen = Set<String>(); var out: [String] = []
        for nm in names where !seen.contains(nm) { seen.insert(nm); out.append(nm) }
        return out.isEmpty ? "this mac" : out.joined(separator: " · ")
    }

    @ViewBuilder private func presenceGlyph(_ a: AgentActivity) -> some View {
        switch a {
        case .waiting:  Text("⚑").font(.system(size: 11.5)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
        case .running:  ShioBrailleSpinner(status: .info, size: 11)
        case .finished: Text("✓").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.success)
        case .none:     Text("⎇").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
        }
    }

    private func gitProbe(_ repo: Repo) -> GitProbe? {
        guard let c = repo.activeCheckout else { return nil }
        return status.status(forHost: c.host, path: c.path)?.probe
    }
}

/// The one live cursor on the overview — a hard blink (the sanctioned motion),
/// stateless so it pauses off-screen. Trails the most-recent project's whisper.
private struct ShioCardCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { ctx in
            let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            Rectangle()
                .fill(ShioTheme.textTertiary)
                .frame(width: 6, height: 12)
                .opacity(on ? 0.9 : 0)
                .padding(.leading, 4)
        }
    }
}
