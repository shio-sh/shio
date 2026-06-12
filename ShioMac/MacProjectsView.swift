import SwiftUI
import SwiftData

/// The dashboard canvas — the LANDING when you switch teams. The selected
/// project's overview: a 48pt header (name + quiet counts + Rename/New repo),
/// the glance strip, and the BENTO — outline-only cards that fill on hover,
/// laid on a real grid so every edge lands (conversations spans two rows;
/// machines + integrations share the bottom row).
struct MacDashboardCanvas: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Environment(\.shioHeaderLeadingInset) private var headerInset
    @State private var renaming = false

    var body: some View {
        Group {
            if let project = model.selectedProject {
                let rows = ProjectRows.rows(for: project)
                let glance = ProjectRows.glance(for: project, rows: rows)
                VStack(spacing: 0) {
                    head(project, glance: glance)
                    MacProjectDashboard(
                        project: project,
                        repos: rows,
                        glance: glance,
                        openRepo: { model.open(repo: $0) },
                        addRepo: { model.addRepoToProject = project },
                        openMachines: { model.canvas = .machines }
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
                    .layoutPriority(1)
            }
            // The sub compresses first when the canvas gets narrow — middle
            // truncation, never an overflow past the header's bounds.
            Text(headSub(project, glance: glance))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 10)
            ShioButton(renaming ? "Done" : "Rename", .secondary, compact: true) {
                if renaming { try? context.save() }
                renaming.toggle()
            }
            .fixedSize()
            ShioButton("New repo", .primary, compact: true) {
                model.addRepoToProject = project
            }
            .fixedSize()
            MacHeaderIconButton(systemImage: "sidebar.trailing", help: "Inspector (⌘I)",
                                on: model.inspectorOpen) {
                model.inspectorOpen.toggle()
            }
        }
        .padding(.leading, 18 + headerInset)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity)
        .frame(height: MacChrome.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    private func headSub(_ project: Project, glance: ProjectGlance) -> String {
        guard glance.repoCount > 0 else { return "no repos yet" }
        let machines = max(1, Set(project.allCheckouts.map { $0.host?.persistentModelID }).count)
        var sub = "\(glance.repoCount) repo\(glance.repoCount == 1 ? "" : "s")"
            + " · \(machines) machine\(machines == 1 ? "" : "s")"
        if !glance.age.isEmpty { sub += " · updated \(glance.age) ago" }
        return sub
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

// MARK: - Dashboard body (the bento)

private struct MacProjectDashboard: View {
    @Bindable var project: Project
    let repos: [RepoRowVM]
    let glance: ProjectGlance
    let openRepo: (Repo) -> Void
    let addRepo: () -> Void
    let openMachines: () -> Void
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
                // Conversations spans the left; skills (+ memory, when it has
                // anything to say — the empty-states law) stack beside it.
                BentoRow(ratios: [1.35, 1]) {
                    conversationsCard
                    VStack(spacing: 14) {
                        skillsCard
                        if project.notes?.isEmpty == false {
                            memoryCard   // stretches — bottoms align with conversations
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.bottom, 14)
                // Machines + integrations share the bottom row — bottoms ALIGN.
                // No machines (no repos yet) → the card is non-existent, not a
                // placeholder; integrations keeps its grid slot.
                if ProjectRows.machines(for: project).isEmpty {
                    BentoRow(ratios: [1.35, 1]) {
                        Color.clear
                        integrationsCard
                    }
                } else {
                    BentoRow(ratios: [1.35, 1]) {
                        machinesCard
                        integrationsCard
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .frame(maxWidth: 1180, alignment: .leading)
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

    // MARK: glance strip (unboxed, above the bento)

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
                glanceItem { Text("⚑").foregroundStyle(ShioTheme.warning).shioNeedsPulse() } label: {
                    Text("\(glance.needsYou) needs you").foregroundStyle(ShioTheme.warning)
                }
            }
            if glance.changes == 0 && glance.working == 0 && glance.needsYou == 0 {
                Text("all quiet").font(.system(size: 12.5)).foregroundStyle(ShioTheme.textTertiary)
            }
            Spacer()
            // Honest about held sleep — invisibly preventing it erodes trust.
            if PowerKeeper.shared.isHolding {
                Text("keeping this mac awake")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            if glance.prs > 0 {
                Text("\(glance.prs) PR\(glance.prs == 1 ? "" : "s") open")
                    .font(.system(size: 12.5)).foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
        .padding(.bottom, 18)
    }

    private func glanceItem<Icon: View, Label: View>(@ViewBuilder icon: () -> Icon,
                                                      @ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: 7) { icon(); label().foregroundStyle(ShioTheme.textSecondary) }
    }

    // MARK: cards

    private var conversationsCard: some View {
        BentoCard(title: "conversations", addLabel: "+ repo", addAction: addRepo) {
            if repos.isEmpty {
                cardHint("No conversations yet — add a repo.")
            } else {
                ForEach(repos) { row in
                    ChanRow(row: row,
                            open: { openRepo(row.repo) },
                            approve: replyAction(row, key: "y"),
                            deny: replyAction(row, key: "n"),
                            onCommit: { commitTarget = row },
                            openOn: { checkout in
                                // Mark the chosen machine most-recent → it becomes
                                // the active checkout → open() picks it up.
                                checkout.lastOpenedAt = .now
                                try? context.save()
                                openRepo(row.repo)
                            })
                }
            }
        }
    }

    /// Inline Approve/Deny exists only when the blocked agent is in THIS Mac's
    /// tmux — a remote one answers from inside its conversation.
    private func replyAction(_ row: RepoRowVM, key: String) -> (() -> Void)? {
        guard row.agent == .waiting,
              let session = MacProjectAgentMonitor.shared.waitingSessionName(forProjectNamed: row.name)
        else { return nil }
        return { MacProjectAgentMonitor.shared.send(key: key, toSession: session) }
    }

    private var skillsCard: some View {
        BentoCard(title: "skills", addLabel: "+ add", addAction: { addingSkill = true }, stretch: false) {
            if globalSkills.isEmpty && projectSkills.isEmpty {
                cardHint("No skills yet — add one here, or build the global library in Settings.")
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
                Text("✓").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.success)
                Text(skill.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
                Spacer()
                ShioChip(text: scope, status: scope == "project" ? .accent : .neutral)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var memoryCard: some View {
        BentoCard(title: "memory & context") {
            cardRow(glyph: "✎", name: "Notes", meta: "edited")
        }
    }

    private var machinesCard: some View {
        BentoCard(title: "machines with this project") {
            ForEach(ProjectRows.machines(for: project)) { m in
                MachineCardRow(summary: m, open: openMachines)
            }
        }
    }

    private var integrationsCard: some View {
        BentoCard(title: "integrations") {
            cardRow(glyph: "◑", name: "GitHub",
                    meta: glance.prs > 0 ? "via gh · \(glance.prs) PR\(glance.prs == 1 ? "" : "s")" : "via gh",
                    glyphColor: ShioTheme.accent)
        }
    }

    private func cardHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func cardRow(glyph: String, name: String, meta: String,
                         glyphColor: Color = ShioTheme.textTertiary) -> some View {
        HStack(spacing: 10) {
            Text(glyph).font(.system(size: 12)).foregroundStyle(glyphColor).frame(width: 14)
            Text(name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
            Spacer()
            Text(meta).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
    }
}

/// One machine in the machines card — clicking it lands on the Machines
/// canvas (the card looked tappable; now it is).
private struct MachineCardRow: View {
    let summary: ProjectRows.MachineSummary
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                ShioStatusDot(status: summary.reachable ? .success : .neutral, filled: summary.reachable)
                Text(summary.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
                Spacer()
                Text(hovering ? "open ›" : summary.detail)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(hovering ? ShioTheme.textSecondary : ShioTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? ShioTheme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Bento plumbing

/// One bento row: children laid out side by side at fixed ratios, every child
/// offered the full row height — so bottoms align ("every edge lands").
private struct BentoRow: Layout {
    var ratios: [CGFloat]
    var spacing: CGFloat = 14

    private func widths(total: CGFloat, count: Int) -> [CGFloat] {
        let usable = max(0, total - spacing * CGFloat(count - 1))
        let sum = ratios.reduce(0, +)
        return (0..<count).map { usable * (ratios.indices.contains($0) ? ratios[$0] : 1) / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 800
        let ws = widths(total: total, count: subviews.count)
        let h = zip(subviews, ws)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(total: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (i, sub) in subviews.enumerated() {
            sub.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                      proposal: ProposedViewSize(width: ws[i], height: bounds.height))
            x += ws[i] + spacing
        }
    }
}

/// A bento card: OUTLINE-ONLY at rest (1px hairline, 11pt radius, transparent),
/// surface fill on hover. UPPERCASE mono header with an optional quiet action.
private struct BentoCard<Content: View>: View {
    let title: String
    var addLabel: String? = nil
    var addAction: (() -> Void)? = nil
    /// Stretch to fill the row height (grid alignment); false = natural height.
    var stretch: Bool = true
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(ShioTheme.textTertiary)
                Spacer(minLength: 4)
                if let addLabel, let addAction {
                    Button(action: addAction) {
                        Text(addLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
            content()
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 9, trailing: 14))
        .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? ShioTheme.surface : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(ShioTheme.line2, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Conversation (channel) row

/// One repo's standing conversation inside the conversations card: presence
/// glyph + name + PR chip, then the live second line — the agent's question
/// with inline Approve/Deny when it needs you, the working detail while it
/// runs, or quiet git state at rest.
private struct ChanRow: View {
    let row: RepoRowVM
    let open: () -> Void
    var approve: (() -> Void)? = nil
    var deny: (() -> Void)? = nil
    var onCommit: (() -> Void)? = nil
    var openOn: ((ProjectCheckout) -> Void)? = nil
    @State private var hovering = false

    private func machineLabel(_ c: ProjectCheckout) -> String {
        (c.host.map(MacSelfHost.isThisMac) ?? true) ? "This Mac" : (c.host?.name ?? "Unknown")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                presence
                Text(row.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                if let pr = row.prs.first(where: { $0.state == "OPEN" }) {
                    ShioChip(text: "PR #\(pr.number)", status: pr.isDraft ? .neutral : .info)
                }
                if hovering {
                    Text("open ›").font(.system(size: 12)).foregroundStyle(ShioTheme.textSecondary)
                }
            }
            secondLine
        }
        .padding(.horizontal, 10).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(hovering ? ShioTheme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { open() }
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

    @ViewBuilder private var presence: some View {
        switch row.agent {
        case .waiting:
            Text("⚑").font(.system(size: 12)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
        case .running:
            ShioBrailleSpinner(status: .info, size: 12)
        default:
            Text("⎇").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
        }
    }

    @ViewBuilder private var secondLine: some View {
        let m = GitLineFormatter.make(row.git)
        HStack(spacing: 12) {
            switch row.agent {
            case .waiting:
                Text(agentLine(quoted: true))
                    .foregroundStyle(ShioTheme.warning)
                    .lineLimit(1).truncationMode(.tail)
                if let approve { MacMiniButton(title: "Approve · y", status: .success, action: approve) }
                if let deny { MacMiniButton(title: "Deny · n", status: .danger, action: deny) }
                Spacer(minLength: 0)
            case .running:
                HStack(spacing: 6) {
                    ShioBrailleSpinner(status: .info, size: 11)
                    Text(agentLine(quoted: false)).foregroundStyle(ShioTheme.info)
                        .lineLimit(1).truncationMode(.tail)
                }
                gitSegs(m)
                Spacer(minLength: 0)
            default:
                gitSegs(m)
                Spacer(minLength: 0)
                Text(row.machines).foregroundStyle(ShioTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .monospacedDigit()
    }

    @ViewBuilder private func gitSegs(_ m: GitLineModel) -> some View {
        HStack(spacing: 6) {
            Text("⎇").foregroundStyle(ShioTheme.textTertiary)
            Text(m.branch).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(m.state == .loading || m.state == .unreachable
                                 ? ShioTheme.textTertiary : ShioTheme.textSecondary)
        }
        if m.hasTracking {
            if m.ahead > 0 { Text("↑\(m.ahead)").foregroundStyle(ShioTheme.textSecondary) }
            if m.behind > 0 { Text("↓\(m.behind)").foregroundStyle(ShioTheme.textSecondary) }
            if m.dirty > 0 {
                HStack(spacing: 6) {
                    ShioStatusDot(status: .warning)
                    Text("\(m.dirty)").foregroundStyle(ShioTheme.warning)
                }
            } else {
                Text("clean").foregroundStyle(ShioTheme.success)
            }
        }
    }

    private func agentLine(quoted: Bool) -> String {
        let name = row.agentName ?? "Agent"
        guard let d = row.agentDetail, !d.isEmpty else { return name }
        return quoted ? "\(name) · \u{201C}\(d)\u{201D}" : "\(name) · \(d)"
    }
}
