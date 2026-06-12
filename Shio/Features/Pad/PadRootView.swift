import SwiftUI
import SwiftData

/// iPad = the Mac layout, touch-sized: ONE rail (project switcher +
/// AGENTS/SHELLS/REPOS + utility rows + 塩 foot), a center canvas (the team's
/// dashboard as the landing, a conversation's terminal, Machines, Files), and
/// the GLANCE inspector — open by default, ▤ everywhere, headers at one fixed
/// height so the hairlines run as one line (the alignment law).
struct PadRootView: View {
    enum Canvas: Equatable {
        case dashboard
        case conversation(UUID)   // SessionStore.Session id
        case machines
        case files
    }

    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Host.name) private var hosts: [Host]
    @Environment(\.modelContext) private var context
    @AppStorage("shio.ios.project") private var selectedName: String = ""
    @AppStorage("shio.pad.inspector") private var inspectorOpen = true
    @State private var canvas: Canvas = .dashboard
    @State private var isAddingProject = false
    @State private var noCheckoutName: String?
    private let sessionStore = SessionStore.shared
    private let status = ProjectStatusStore.shared

    private var selected: Project? {
        projects.first { $0.name == selectedName } ?? projects.first
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(ShioTheme.line).frame(width: 1)
            center
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if inspectorOpen {
                Rectangle().fill(ShioTheme.line).frame(width: 1)
                PadInspector(project: selected, contextRepo: conversationRepo,
                             close: { inspectorOpen = false })
            }
        }
        .background(ShioTheme.background)
        .sheet(isPresented: $isAddingProject) { AddProjectSheet() }
        .alert("No machine for this repo", isPresented: Binding(
            get: { noCheckoutName != nil }, set: { if !$0 { noCheckoutName = nil } })) {
            Button("OK") { noCheckoutName = nil }
        } message: {
            Text("“\(noCheckoutName ?? "")” has no checkout on a reachable machine yet.")
        }
        .onAppear { refreshStatus() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                status.refresh(ProjectStatusStore.targets(
                    for: projects, isLocalHost: { _ in false }, warmOnly: true))
            }
        }
    }

    // MARK: rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 18)
            switcher
                .padding(.horizontal, 10)
            Rectangle().fill(ShioTheme.line)
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    groups
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            utility
            Text("塩 shio")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .padding(.leading, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(width: 236)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ShioTheme.rail)
    }

    @ViewBuilder private var switcher: some View {
        if let project = selected {
            Menu {
                ForEach(projects) { p in
                    Button { select(p) } label: {
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
                HStack(spacing: 9) {
                    Text(String(project.name.first ?? "•").uppercased())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShioTheme.accent)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ShioTheme.accentBg))
                    Text(project.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShioTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ShioTheme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Button { isAddingProject = true } label: {
                HStack(spacing: 9) {
                    Text("+")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ShioTheme.hover))
                    Text("New project…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShioTheme.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var groups: some View {
        let items = presenceItems
        if !items.isEmpty {
            railHeader("agents")
            ForEach(items) { item in
                railRow(title: "\(item.agentName) · \(item.repoName)",
                        selected: isOpenConversation(named: item.repoName),
                        action: { jump(item.repo) }) {
                    presenceGlyph(item.activity)
                } trailing: {
                    if item.activity == .waiting {
                        Text("needs you")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ShioTheme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(ShioTheme.warning.opacity(0.4), lineWidth: 1))
                    }
                }
            }
        }
        if !dedupedHosts.isEmpty {
            railHeader("shells")
                .padding(.top, items.isEmpty ? 0 : 6)
            ForEach(dedupedHosts) { host in
                railRow(title: host.name,
                        selected: isOpenShell(host),
                        action: { openShell(host) }) {
                    Text("%").font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary)
                } trailing: { EmptyView() }
            }
        }
        if let project = selected, !project.sortedRepos.isEmpty {
            railHeader("repos")
                .padding(.top, 6)
            ForEach(project.sortedRepos) { repo in
                railRow(title: repo.name,
                        selected: isOpenConversation(named: repo.name),
                        action: { jump(repo) }) {
                    Text("⎇").font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary)
                } trailing: {
                    let dirty = dirtyCount(repo)
                    if dirty > 0 {
                        Text("\(dirty)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ShioTheme.warning)
                    }
                }
            }
        }
    }

    private var utility: some View {
        VStack(alignment: .leading, spacing: 2) {
            railRow(title: "Machines", muted: true,
                    selected: canvas == .machines,
                    action: { canvas = .machines }) {
                Text("⌗").font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            } trailing: {
                Text("\(dedupedHosts.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            railRow(title: "Files", muted: true,
                    selected: canvas == .files,
                    action: { canvas = .files }) {
                Text("▤").font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            } trailing: { EmptyView() }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    private func railHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(2)
            .foregroundStyle(ShioTheme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 5)
    }

    private func railRow<Icon: View, Trailing: View>(
        title: String, muted: Bool = false, selected: Bool, action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon, @ViewBuilder trailing: () -> Trailing) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon().frame(width: 13)
                Text(title)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(selected ? ShioTheme.accent
                                     : (muted ? ShioTheme.textSecondary : ShioTheme.textPrimary))
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? ShioTheme.accentBg : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func presenceGlyph(_ activity: AgentActivity) -> some View {
        switch activity {
        case .waiting:
            Text("⚑").font(.system(size: 11.5)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
        case .running:
            ShioBrailleSpinner(status: .info, size: 11.5)
        case .finished:
            Text("✓").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(ShioTheme.success)
        case .none:
            EmptyView()
        }
    }

    // MARK: center

    @ViewBuilder private var center: some View {
        switch canvas {
        case .dashboard:
            if let project = selected {
                NavigationStack {
                    ProjectOverviewView(project: project,
                                        openRepo: { jump($0) },
                                        openProject: { if let r = project.activeRepo { jump(r) } })
                }
                .id(project.persistentModelID)
            } else {
                padEmptyState
            }
        case .conversation(let id):
            if let session = sessionStore.sessions.first(where: { $0.id == id }) {
                PadConversationView(session: session,
                                    inspectorOpen: inspectorOpen,
                                    toggleInspector: { inspectorOpen.toggle() })
            } else {
                // The session closed under us — land back on the dashboard.
                Color.clear.onAppear { canvas = .dashboard }
            }
        case .machines:
            NavigationStack { HostListView() }
        case .files:
            NavigationStack { FilesView() }
        }
    }

    private var padEmptyState: some View {
        VStack(spacing: ShioSpace.md) {
            Text("塩").font(ShioFont.kanji(size: 72)).foregroundStyle(ShioTheme.textTertiary)
            Text("No projects yet")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("Add a repo from a machine you've connected, and it lives here.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            ShioButton("Add a project", .primary, icon: "plus") { isAddingProject = true }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioTheme.background)
    }

    // MARK: data + actions

    private var dedupedHosts: [Host] { hosts.dedupedByIdentity }

    private var presenceItems: [ActivityItem] {
        guard let project = selected else { return [] }
        return project.sortedRepos.compactMap { repo -> ActivityItem? in
            guard let p = ActivityFeed.presence(for: repo) else { return nil }
            return ActivityItem(id: repo.name, activity: p.snap.activity,
                                agentName: p.snap.agentName ?? "Agent",
                                detail: p.snap.detail, repoName: repo.name,
                                projectName: project.name, age: shioShortAge(p.at),
                                repo: repo, sessionID: p.sessionID)
        }
    }

    private func isOpenConversation(named name: String) -> Bool {
        guard case .conversation(let id) = canvas,
              let session = sessionStore.sessions.first(where: { $0.id == id }) else { return false }
        return session.displayName == name
    }

    private func isOpenShell(_ host: Host) -> Bool {
        guard case .conversation(let id) = canvas,
              let session = sessionStore.sessions.first(where: { $0.id == id }) else { return false }
        return session.projectID == nil && session.hostID == host.persistentModelID
    }

    private func select(_ project: Project) {
        selectedName = project.name
        project.lastOpenedAt = .now
        try? context.save()
        canvas = .dashboard   // switching teams lands on the dashboard
    }

    private func jump(_ repo: Repo) {
        if let project = repo.project, project.persistentModelID != selected?.persistentModelID {
            selectedName = project.name
        }
        if let session = sessionStore.openOrCreate(repo: repo) {
            canvas = .conversation(session.id)
        } else {
            noCheckoutName = repo.name
        }
    }

    private func openShell(_ host: Host) {
        let session = sessionStore.openOrCreate(host: host)
        canvas = .conversation(session.id)
    }

    private func dirtyCount(_ repo: Repo) -> Int {
        guard let c = repo.activeCheckout else { return 0 }
        return GitLineFormatter.make(status.status(forHost: c.host, path: c.path)?.probe).dirty
    }

    private var conversationRepo: Repo? {
        guard case .conversation(let id) = canvas,
              let session = sessionStore.sessions.first(where: { $0.id == id }),
              let project = selected else { return nil }
        return project.sortedRepos.first { $0.name == session.displayName }
    }

    private func refreshStatus() {
        let targets = ProjectStatusStore.targets(for: projects, isLocalHost: { _ in false })
        status.refresh(targets)
        status.refreshPRs(targets)
    }
}

// MARK: - Conversation canvas

/// A conversation inline on the iPad canvas: 44pt header (presence + name +
/// quiet metadata + ▤), the terminal, and the answer bar while its agent is
/// blocked.
private struct PadConversationView: View {
    let session: SessionStore.Session
    let inspectorOpen: Bool
    let toggleInspector: () -> Void

    private var snapshot: AgentSnapshot? {
        AgentStateStore.shared.snapshot(for: session.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            ZStack {
                Color(hex: LibGhosttyBridge.terminalBackgroundHex)
                    .ignoresSafeArea(edges: .bottom)
                TerminalView(controller: session.viewModel.terminal)
                    .id(session.id)
                if case .connecting = session.viewModel.state {
                    ProgressView().tint(ShioTheme.textPrimary)
                }
                if case .disconnected(let reason) = session.viewModel.state {
                    VStack(spacing: 10) {
                        Text(reason ?? "Disconnected")
                            .font(.system(size: 13))
                            .foregroundStyle(ShioTheme.textSecondary)
                        ShioButton("Reconnect", .primary, compact: true) {
                            Task { await session.viewModel.start() }
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let snap = snapshot, snap.activity == .waiting {
                    HStack(spacing: 9) {
                        Text("⚑").font(.system(size: 12)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
                        Text("\(snap.agentName ?? "Your agent") is waiting")
                            .font(.system(size: 12.5))
                            .foregroundStyle(ShioTheme.textPrimary)
                        Spacer(minLength: 8)
                        ShioMiniButton(title: "Approve", status: .success) {
                            Haptics.medium()
                            session.viewModel.terminal.onInput?("y\n")
                        }
                        ShioMiniButton(title: "Deny", status: .danger) {
                            Haptics.medium()
                            session.viewModel.terminal.onInput?("n\n")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ShioTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ShioTheme.warningBg))
                    .overlay(alignment: .leading) { Rectangle().fill(ShioTheme.warning).frame(width: 2) }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                    .padding(12)
                }
            }
        }
        .onAppear { SessionStore.shared.activeSession = session }
        .task(id: session.id) {
            if case .idle = session.viewModel.state {
                await session.viewModel.start()
            }
        }
    }

    private var head: some View {
        HStack(spacing: 10) {
            Group {
                switch snapshot?.activity {
                case .waiting:
                    Text("⚑").font(.system(size: 12)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
                case .running:
                    ShioBrailleSpinner(status: .info, size: 12)
                default:
                    Text(session.projectID == nil ? "%" : "⎇")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary)
                }
            }
            Text(session.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1)
            Text(sub)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 10)
            Button(action: toggleInspector) {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(inspectorOpen ? ShioTheme.accent : ShioTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(inspectorOpen ? ShioTheme.accentBg : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inspector")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(ShioTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    private var sub: String {
        let agent = snapshot?.agentName
        let place = "tmux · \(session.viewModel.hostName)"
        return [agent, place].compactMap(\.self).joined(separator: " · ")
    }
}

// MARK: - Inspector

/// The GLANCE panel — 44pt head colinear with the conversation header.
private struct PadInspector: View {
    let project: Project?
    let contextRepo: Repo?
    let close: () -> Void
    private let status = ProjectStatusStore.shared

    var body: some View {
        VStack(spacing: 0) {
            head
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    groups
                }
                .padding(14)
            }
        }
        .frame(width: 230)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ShioTheme.background)
    }

    private var head: some View {
        HStack {
            Text("GLANCE")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ShioTheme.textTertiary)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close inspector")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    @ViewBuilder private var groups: some View {
        if let project {
            let items = project.sortedRepos.compactMap { ActivityFeed.presence(for: $0) }
            let changes = project.sortedRepos.reduce(0) { $0 + dirtyCount($1) }
            let working = items.filter { $0.snap.activity == .running }.count
            let needs = items.filter { $0.snap.activity == .waiting }.count
            let prs = project.sortedRepos.reduce(0) { $0 + openPRCount($1) }

            if changes == 0 && working == 0 && needs == 0 && prs == 0 {
                Text("all quiet")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ShioTheme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if changes > 0 {
                        kv("Changes") { Text("\(changes)").foregroundStyle(ShioTheme.warning) }
                    }
                    if working > 0 || needs > 0 {
                        kv("Agents") {
                            HStack(spacing: 5) {
                                if working > 0 {
                                    ShioBrailleSpinner(status: .info, size: 10)
                                    Text("\(working)").foregroundStyle(ShioTheme.info)
                                }
                                if working > 0 && needs > 0 {
                                    Text("·").foregroundStyle(ShioTheme.textTertiary)
                                }
                                if needs > 0 {
                                    Text("⚑ \(needs)").foregroundStyle(ShioTheme.warning)
                                }
                            }
                        }
                    }
                    if prs > 0 {
                        kv("PRs open") { Text("\(prs)").foregroundStyle(ShioTheme.textPrimary) }
                    }
                }
            }

            if let repo = contextRepo {
                repoGroup(repo)
            }
        } else {
            Text("No project yet")
                .font(.system(size: 11.5))
                .foregroundStyle(ShioTheme.textTertiary)
        }
    }

    private func repoGroup(_ repo: Repo) -> some View {
        let m = GitLineFormatter.make(
            repo.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe })
        return VStack(alignment: .leading, spacing: 0) {
            Text("THIS REPO")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ShioTheme.textTertiary)
                .padding(.bottom, 6)
            kv("⎇ Branch") {
                Text(m.branch).foregroundStyle(ShioTheme.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if m.hasTracking {
                kv("Dirty") {
                    if m.dirty > 0 {
                        Text("\(m.dirty) file\(m.dirty == 1 ? "" : "s")").foregroundStyle(ShioTheme.warning)
                    } else {
                        Text("clean").foregroundStyle(ShioTheme.success)
                    }
                }
            }
        }
    }

    private func kv<V: View>(_ key: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 8) {
            Text(key).foregroundStyle(ShioTheme.textSecondary)
            Spacer(minLength: 8)
            value()
        }
        .font(.system(size: 11.5, design: .monospaced))
        .monospacedDigit()
        .padding(.vertical, 4)
    }

    private func dirtyCount(_ repo: Repo) -> Int {
        guard let c = repo.activeCheckout else { return 0 }
        return GitLineFormatter.make(status.status(forHost: c.host, path: c.path)?.probe).dirty
    }

    private func openPRCount(_ repo: Repo) -> Int {
        guard let c = repo.activeCheckout else { return 0 }
        return status.prList(forHost: c.host, path: c.path).filter { $0.state == "OPEN" }.count
    }
}
