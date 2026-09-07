import SwiftUI
import SwiftData

/// Home — the command center: an OVERVIEW of every project across every
/// machine. You land here, not inside a project; tap one to drop into its
/// dashboard. Titled ~/shio — your root.
struct HomeTabView: View {

    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @State private var showingSettings = false
    @State private var isAddingProject = false
    @State private var selectedProject: Project?
    private let status = ProjectStatusStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(projects) { project in
                                HomeProjectCard(
                                    project: project,
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
            // Cheap keep-fresh while the overview is on screen — git state
            // updates without a manual pull. warmOnly so it never wakes a
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
        ModelCascade.delete(project: project, context: context)
        try? context.save()
    }

    // MARK: - Status reads

    private func refreshStatus() {
        let targets = ProjectStatusStore.targets(for: projects, isLocalHost: { _ in false })
        status.refresh(targets)
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


// MARK: - Home project card

/// One project in the overview — a calm whisper card: the identity-tinted
/// mark, the name, and one faint terminal line (the project's git state);
/// the most-recent project carries a live blinking cursor.
private struct HomeProjectCard: View {
    let project: Project
    let changes: Int
    let isMostRecent: Bool
    let open: () -> Void
    private let status = ProjectStatusStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 13)
            whisper.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(ShioTheme.line2, lineWidth: 1)
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
        ProjectAvatar(project, size: 30)
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
