import SwiftUI
import SwiftData

/// The project dashboard body — ONE bento for the Mac and iPad canvases:
/// the glance strip, repos + skills/memory cards, machines + integrations.
/// Rows/glance/machines arrive pre-built (`ProjectRows` on the Mac, the
/// `ActivityFeed` builder on iOS); everything platform-bound — opening a
/// repo, answering a blocked agent, "is this host me" — is injected, so the
/// dashboard itself stays a pure read of the shared stores.
struct ProjectDashboardView: View {
    @Bindable var project: Project
    let repos: [RepoRowVM]
    let glance: ProjectGlance
    let machines: [MachineSummary]
    let openRepo: (Repo) -> Void
    let addRepo: () -> Void
    let openMachines: () -> Void
    /// The platform's answer path for a blocked row — nil when it can't be
    /// answered from here (the Mac only answers agents in its own tmux).
    let reply: (RepoRowVM, String) -> (() -> Void)?
    /// Whether a checkout's host is THIS machine (nil host = the Mac itself
    /// on the Mac; never true on iOS) — picks the commit sheet's local/SSH path.
    let isLocalHost: (Host?) -> Bool

    @Environment(\.modelContext) private var context
    @Query(sort: \Skill.createdAt) private var allSkills: [Skill]
    @State private var addingSkill = false
    @State private var editingSkill: Skill?
    @State private var commitTarget: RepoRowVM?
    @State private var renameTarget: Repo?
    @State private var renameDraft = ""
    @State private var editingNotes = false

    private var globalSkills: [Skill] { allSkills.filter { $0.isGlobal && $0.enabled } }
    private var projectSkills: [Skill] {
        allSkills.filter { $0.project?.persistentModelID == project.persistentModelID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                glanceBar
                // Repos spans the left; skills (+ memory, when it has
                // anything to say — the empty-states law) stack beside it.
                BentoRow(ratios: [1.35, 1]) {
                    reposCard
                    VStack(spacing: 14) {
                        skillsCard
                        if project.notes?.isEmpty == false {
                            memoryCard   // stretches — bottoms align with repos
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.bottom, 14)
                // Machines + integrations share the bottom row — bottoms ALIGN.
                // No machines (no repos yet) → the card is non-existent, not a
                // placeholder; integrations keeps its grid slot.
                if machines.isEmpty {
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
            let config: SSHClient.Configuration? = (host != nil && !isLocalHost(host))
                ? SSHClient.Configuration(host: host!.hostname, port: host!.port, username: host!.username,
                                          authentication: .systemKeys, initialCols: 80, initialRows: 24)
                : nil
            CommitSheet(repoName: row.name, dirtyCount: GitLineFormatter.make(row.git).dirty,
                        path: c?.path ?? "", config: config,
                        onCommitted: {
                            // Clear the dirty badge right away, not on the next tick.
                            ProjectStatusStore.shared.refresh(ProjectStatusStore.targets(
                                for: [project], isLocalHost: { isLocalHost($0) }))
                        })
            #if os(iOS)
            .presentationDetents([.medium])
            #endif
        }
        .sheet(isPresented: $editingNotes) { notesSheet }
        .alert("Rename repo", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameDraft)
            Button("Save") {
                let n = renameDraft.trimmingCharacters(in: .whitespaces)
                if let repo = renameTarget, !n.isEmpty { repo.name = n; try? context.save() }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
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
            #if os(macOS)
            // Honest about held sleep — invisibly preventing it erodes trust.
            if PowerKeeper.shared.isHolding {
                Text("keeping this mac awake")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            #endif
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

    private var reposCard: some View {
        BentoCard(title: "repos", addLabel: "+ repo", addAction: addRepo) {
            if repos.isEmpty {
                cardHint("No repos yet — add one.")
            } else {
                ForEach(repos) { row in
                    ShioRepoRow(row: row,
                                open: { openRepo(row.repo) },
                                approve: reply(row, "y"),
                                deny: reply(row, "n"))
                        .contextMenu { rowMenu(row) }
                }
            }
        }
    }

    @ViewBuilder private func rowMenu(_ row: RepoRowVM) -> some View {
        Button("Rename…", systemImage: "pencil") { renameDraft = row.repo.name; renameTarget = row.repo }
        let checkouts = row.repo.checkouts ?? []
        if checkouts.count > 1 {
            Menu("Open on") {
                ForEach(checkouts, id: \.persistentModelID) { c in
                    Button(machineLabel(c)) {
                        // Mark the chosen machine most-recent → it becomes
                        // the active checkout → open() picks it up.
                        c.lastOpenedAt = .now
                        try? context.save()
                        openRepo(row.repo)
                    }
                }
            }
        }
        if GitLineFormatter.make(row.git).dirty > 0 {
            Button("Commit & push…", systemImage: "arrow.up") { commitTarget = row }
        }
    }

    private func machineLabel(_ c: ProjectCheckout) -> String {
        isLocalHost(c.host) ? "This Mac" : (c.host?.name ?? "Unknown")
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
            Button { editingNotes = true } label: {
                cardRow(glyph: "✎", name: "Notes", meta: "edited")
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    /// The notes editor — saves as you type, like every other project field.
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
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private var machinesCard: some View {
        BentoCard(title: "machines with this project") {
            ForEach(machines) { m in
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

/// One machine in the machines card — tapping it lands on the Machines
/// canvas (the card looked tappable; now it is).
private struct MachineCardRow: View {
    let summary: MachineSummary
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
