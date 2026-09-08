import SwiftUI
import SwiftData

/// The project dashboard body — ONE bento for the Mac and iPad canvases: the
/// glance strip, repos, machines full-width below. Rows/glance/machines
/// arrive pre-built (`ProjectRows` on the Mac, the `ActivityFeed` builder on
/// iOS); everything platform-bound — opening a repo, "is this host me" — is
/// injected, so the dashboard itself stays a pure read of the shared stores.
struct ProjectDashboardView: View {
    @Bindable var project: Project
    let repos: [RepoRowVM]
    let glance: ProjectGlance
    let machines: [MachineSummary]
    let openRepo: (Repo) -> Void
    let addRepo: () -> Void
    let openMachines: () -> Void
    /// Whether a checkout's host is THIS machine (nil host = the Mac itself
    /// on the Mac; never true on iOS).
    let isLocalHost: (Host?) -> Bool

    @Environment(\.modelContext) private var context
    @State private var renameTarget: Repo?
    @State private var renameDraft = ""
    /// A repo with no checkout anywhere. Tapping it can't open a terminal, so
    /// it opens the repair sheet instead — the Mac had no route to this at all
    /// before, which left an unplaced repo as a dead row.
    @State private var repoNeedingHome: Repo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                glanceBar
                reposCard
                // Machines run full-width below. No machines (no repos yet)
                // → the card is non-existent, never a placeholder.
                if !machines.isEmpty {
                    machinesCard.padding(.top, 14)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .frame(maxWidth: 1180, alignment: .leading)
        }
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
        .sheet(item: $repoNeedingHome) { repo in
            RepoRepairSheet(repo: repo) { _ in openRepo(repo) }
        }
    }

    // MARK: glance strip (unboxed, above the bento)

    private var glanceBar: some View {
        HStack(spacing: 18) {
            if glance.changes > 0 {
                glanceItem { ShioStatusDot(status: .warning) } label: {
                    // Text interpolation, not `+` (deprecated in iOS 26) —
                    // keeps the count warning-tinted inside a default-tinted label.
                    Text("\(Text("\(glance.changes)").foregroundStyle(ShioTheme.warning)) changes")
                }
            }
            // "all quiet" used to earn its place by contrasting with an agent
            // needing you. With nothing to contrast against it never said
            // anything, so the strip now carries the project's actual shape.
            Text(shapeSummary).font(.system(size: 12.5)).foregroundStyle(ShioTheme.textTertiary)
            if unplacedCount > 0 {
                glanceItem { ShioStatusDot(status: .warning) } label: {
                    Text(unplacedCount == 1 ? "1 repo not placed"
                                            : "\(unplacedCount) repos not placed")
                }
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
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
        .padding(.bottom, 18)
    }

    /// Repos with no checkout on any machine — they can't be opened or probed.
    private var unplacedCount: Int { repos.filter { !$0.isPlaced }.count }

    /// "3 repos · 2 machines" — the one line that's true whatever else is going on.
    private var shapeSummary: String {
        let r = repos.count
        let m = machines.count
        let repoPart = r == 1 ? "1 repo" : "\(r) repos"
        guard m > 0 else { return repoPart }
        return "\(repoPart) · \(m == 1 ? "1 machine" : "\(m) machines")"
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
                    ShioRepoRow(row: row, open: {
                        if row.isPlaced { openRepo(row.repo) } else { repoNeedingHome = row.repo }
                    })
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
    }

    private func machineLabel(_ c: ProjectCheckout) -> String {
        isLocalHost(c.host) ? "This Mac" : (c.host?.name ?? "Unknown")
    }

    private var machinesCard: some View {
        // Natural height — full-width, nothing left in its row to align with.
        BentoCard(title: "machines with this project", stretch: false) {
            ForEach(machines) { m in
                MachineCardRow(summary: m, open: openMachines)
            }
        }
    }

    private func cardHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 6)
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
