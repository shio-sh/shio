import SwiftUI
import SwiftData

/// Inside a project on iPhone — the Mac rail's AGENTS/SHELLS/REPOS, decomposed
/// for a phone: a needs-you bar, the repos (each a standing terminal) with
/// agent presence, the project's shells, and its grounding (skills · memory ·
/// rename) shown inline. The Slack-style switcher is the only thing in the
/// header (tap the name ▾) — no back button; the Home tab returns you to the
/// overview (his calls).
struct ProjectView: View {
    @State private var project: Project
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @Query(sort: \Skill.createdAt) private var allSkills: [Skill]
    @State private var showingSwitcher = false
    @State private var showingAddRepo = false
    @State private var showingAddProject = false
    @State private var showingTerminal = false
    @State private var showingNotes = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var noCheckoutName: String?
    private let sessionStore = SessionStore.shared
    private let status = ProjectStatusStore.shared

    private var skillsCount: Int {
        allSkills.filter { ($0.isGlobal && $0.enabled) || $0.project?.persistentModelID == project.persistentModelID }.count
    }

    init(project: Project) {
        _project = State(initialValue: project)
    }

    private var needsYou: [ActivityItem] {
        ActivityFeed.items(projects: [project]).filter { $0.activity == .waiting }
    }
    private var machines: [Host] {
        project.allCheckouts.compactMap(\.host).dedupedByIdentity
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                switcherHeader
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(needsYou) { item in needsYouBar(item) }

                        sectionHeader("repos", add: { showingAddRepo = true })
                        if project.sortedRepos.isEmpty {
                            quietHint("No repos yet — add one.")
                        } else {
                            ForEach(project.sortedRepos) { repo in conversationRow(repo) }
                        }

                        if !machines.isEmpty {
                            sectionHeader("shells")
                            ForEach(machines) { host in shellRow(host) }
                        }

                        groundingSection
                    }
                    .padding(.bottom, 16)
                }
            }
            .background(ShioTheme.background)

            if showingSwitcher { switcherOverlay }
        }
        // The Slack switcher is the whole header (top-left, like the touch2
        // mock). No nav bar, no back button — the Home tab returns you to the
        // overview (his calls).
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingNotes) { notesSheet }
        .alert("Rename project", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let n = renameText.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { project.name = n; try? context.save() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingAddRepo) { AddProjectSheet(targetProject: project) }
        .sheet(isPresented: $showingAddProject) { AddProjectSheet() }
        .fullScreenCover(isPresented: $showingTerminal) { TerminalScene() }
        .alert("No machine for this repo", isPresented: Binding(
            get: { noCheckoutName != nil }, set: { if !$0 { noCheckoutName = nil } })) {
            Button("OK") { noCheckoutName = nil }
        } message: {
            Text("“\(noCheckoutName ?? "")” has no checkout on a reachable machine yet.")
        }
        .onAppear { refresh() }
        .onChange(of: project.persistentModelID) { _, _ in refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                status.refresh(ProjectStatusStore.targets(for: [project], isLocalHost: { _ in false }, warmOnly: true))
            }
        }
    }

    // MARK: switcher header (top-left, the touch2 .ph-head)

    private var switcherHeader: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showingSwitcher.toggle() }
        } label: {
            HStack(spacing: 10) {
                projectMark(project, size: 28)
                Text(project.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ShioTheme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .rotationEffect(.degrees(showingSwitcher ? 180 : 0))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch project")
        .background(ShioTheme.background)
    }

    // MARK: needs-you

    private func needsYouBar(_ item: ActivityItem) -> some View {
        HStack(spacing: 9) {
            Text("⚑").font(.system(size: 12)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.agentName) · \(item.repoName)")
                    .font(.system(size: 12.5)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                if let d = item.detail, !d.isEmpty {
                    Text("\"\(d)\"").font(.system(size: 12)).foregroundStyle(ShioTheme.warning).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            ShioMiniButton(title: "Approve", status: .success) {
                Haptics.medium(); ActivityFeed.reply(item, key: "y")
            }
            ShioMiniButton(title: "Deny", status: .danger) {
                Haptics.medium(); ActivityFeed.reply(item, key: "n")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(ShioTheme.warningBg))
        .overlay(alignment: .leading) { Rectangle().fill(ShioTheme.warning).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 14).padding(.top, 10)
    }

    // MARK: conversations

    private func conversationRow(_ repo: Repo) -> some View {
        let presence = ActivityFeed.presence(for: repo)
        let activity = presence?.snap.activity ?? .none
        return Button { openRepo(repo) } label: {
            HStack(spacing: 11) {
                presenceGlyph(activity).frame(width: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name).font(.system(size: 14.5)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                    sub(repo, presence: presence?.snap)
                }
                Spacer(minLength: 8)
                trailingMeta(repo)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1).padding(.leading, 16) }
    }

    @ViewBuilder private func sub(_ repo: Repo, presence: AgentSnapshot?) -> some View {
        switch presence?.activity {
        case .waiting:
            Text("\(presence?.agentName ?? "Agent") · waiting on you")
                .font(.system(size: 11.5)).foregroundStyle(ShioTheme.warning).lineLimit(1)
        case .running:
            Text("\(presence?.agentName ?? "Agent")\(presence?.detail.map { " · \($0)" } ?? "")")
                .font(.system(size: 11.5)).foregroundStyle(ShioTheme.info).lineLimit(1).truncationMode(.tail)
        default:
            let m = GitLineFormatter.make(gitProbe(repo))
            Text("\(m.branch) · \(machineLabel(repo))")
                .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder private func trailingMeta(_ repo: Repo) -> some View {
        let m = GitLineFormatter.make(gitProbe(repo))
        let pr = repo.activeCheckout.flatMap { c in
            status.prList(forHost: c.host, path: c.path).first { $0.state == "OPEN" }
        }
        HStack(spacing: 6) {
            if m.dirty > 0 { Text("\(m.dirty)").foregroundStyle(ShioTheme.warning) }
            if let pr {
                if m.dirty > 0 { Text("·").foregroundStyle(ShioTheme.textTertiary) }
                Text("PR #\(pr.number)").foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .font(.system(size: 11, design: .monospaced)).monospacedDigit()
    }

    // MARK: shells

    private func shellRow(_ host: Host) -> some View {
        Button {
            sessionStore.openOrCreate(host: host)
            showingTerminal = true
        } label: {
            HStack(spacing: 11) {
                Text("%").font(.system(size: 12.5, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary).frame(width: 15)
                Text(host.name).font(.system(size: 14.5)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                if !sessionStore.sessions(for: host.persistentModelID).isEmpty {
                    Text("live").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1).padding(.leading, 16) }
    }

    // MARK: grounding (shown inline — his call, not behind ⓘ)

    @ViewBuilder private var groundingSection: some View {
        sectionHeader("grounding")
        NavigationLink { SkillsLibraryView() } label: {
            moduleRow(icon: "wrench.and.screwdriver", name: "Skills",
                      detail: skillsCount == 0 ? "add" : "\(skillsCount) active")
        }
        .buttonStyle(.plain)
        Button { showingNotes = true } label: {
            moduleRow(icon: "doc.text", name: "Memory & context",
                      detail: (project.notes?.isEmpty == false) ? "notes" : "add")
        }
        .buttonStyle(.plain)
        Button { renameText = project.name; showingRename = true } label: {
            moduleRow(icon: "pencil", name: "Rename project", detail: "")
        }
        .buttonStyle(.plain)
    }

    private func moduleRow(icon: String, name: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(ShioTheme.textSecondary).frame(width: 18)
            Text(name).font(.system(size: 14.5)).foregroundStyle(ShioTheme.textPrimary)
            Spacer()
            if !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(ShioTheme.textTertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 13).frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1).padding(.leading, 16) }
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

    // MARK: switcher overlay

    private var switcherOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { showingSwitcher = false } }
            VStack(alignment: .leading, spacing: 0) {
                Text("SWITCH PROJECT")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced)).tracking(2)
                    .foregroundStyle(ShioTheme.textTertiary)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
                ForEach(projects) { p in switcherRow(p) }
                Rectangle().fill(ShioTheme.line).frame(height: 1).padding(.vertical, 2)
                Button { showingSwitcher = false; showingAddProject = true } label: {
                    HStack(spacing: 11) {
                        Text("+").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ShioTheme.hover))
                        Text("New project…").font(.system(size: 14.5)).foregroundStyle(ShioTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ShioTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ShioTheme.line2, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 7)
            .padding(.horizontal, 12)
            .padding(.top, 52)   // drop just below the switcher header
        }
    }

    private func switcherRow(_ p: Project) -> some View {
        let current = p.persistentModelID == project.persistentModelID
        let act = ActivityFeed.items(projects: [p]).map(\.activity)
        return Button {
            project = p
            p.lastOpenedAt = .now
            try? context.save()
            withAnimation(.easeOut(duration: 0.12)) { showingSwitcher = false }
        } label: {
            HStack(spacing: 11) {
                projectMark(p, size: 24, muted: !current)
                Text(p.name).font(.system(size: 14.5)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                Spacer(minLength: 6)
                if act.contains(.waiting) {
                    Text("⚑").font(.system(size: 11)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
                } else if act.contains(.running) {
                    ShioBrailleSpinner(status: .info, size: 11)
                } else {
                    let age = shioShortAge(p.lastOpenedAt)
                    if !age.isEmpty { Text(age).font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary) }
                }
                if current { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(ShioTheme.accent) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: shared bits

    private func projectMark(_ p: Project, size: CGFloat, muted: Bool = false) -> some View {
        Text(String(p.name.first ?? "•").uppercased())
            .font(.system(size: size * 0.5, weight: .medium, design: .monospaced))
            .foregroundStyle(muted ? ShioTheme.textTertiary : ShioTheme.accent)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(muted ? ShioTheme.hover : ShioTheme.accentBg))
    }

    @ViewBuilder private func presenceGlyph(_ a: AgentActivity) -> some View {
        switch a {
        case .waiting:  Text("⚑").font(.system(size: 12.5)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
        case .running:  ShioBrailleSpinner(status: .info, size: 12)
        case .finished: Text("✓").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.success)
        case .none:     Text("⎇").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
        }
    }

    private func sectionHeader(_ title: String, add: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .medium, design: .monospaced)).tracking(2)
                .foregroundStyle(ShioTheme.textTertiary)
            Spacer()
            if let add {
                Button(action: add) {
                    Text("+ repo").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
    }

    private func quietHint(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(ShioTheme.textTertiary)
            .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func machineLabel(_ repo: Repo) -> String {
        repo.activeCheckout?.host?.name ?? "this mac"
    }
    private func gitProbe(_ repo: Repo) -> GitProbe? {
        guard let c = repo.activeCheckout else { return nil }
        return status.status(forHost: c.host, path: c.path)?.probe
    }

    private func openRepo(_ repo: Repo) {
        if sessionStore.openOrCreate(repo: repo) != nil { showingTerminal = true }
        else { noCheckoutName = repo.name }
    }

    private func refresh() {
        let targets = ProjectStatusStore.targets(for: [project], isLocalHost: { _ in false })
        status.refresh(targets)
        status.refreshPRs(targets)
    }
}
