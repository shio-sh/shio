import SwiftUI
import SwiftData

/// The project dashboard on iPhone — supervision-first, reordered for mobile:
/// a one-line glance, then **needs-you** and **agents** up top (the away
/// use-case), repos next, and the grounding/config modules as tap-in rows.
/// Built on the terminal-refined kit. Live now: repos (git) + agents (from open
/// sessions). Approve/deny on a needs-you card arrives with remote control (P6);
/// for now the card jumps you into the terminal to answer.
struct ProjectOverviewView: View {
    @Bindable var project: Project
    let openRepo: (Repo) -> Void
    let openProject: () -> Void
    @Environment(\.modelContext) private var context
    private let status = ProjectStatusStore.shared
    private let sessionStore = SessionStore.shared
    private let agents = AgentStateStore.shared

    @State private var showingAddRepo = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingNotes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                glanceBar
                if !needsYou.isEmpty {
                    sectionHeader("needs you")
                    ForEach(needsYou, id: \.0.id) { (s, snap) in
                        needsYouCard(session: s, snap: snap)
                    }
                }
                if !working.isEmpty {
                    sectionHeader("agents")
                    ForEach(working, id: \.0.id) { (s, snap) in
                        agentRow(session: s, snap: snap)
                    }
                }
                sectionHeader("repos", add: { showingAddRepo = true })
                ForEach(project.sortedRepos) { repo in repoRow(repo) }

                sectionHeader("grounding")
                moduleRow(icon: "wrench.and.screwdriver", name: "Skills", detail: "soon")
                Button { showingNotes = true } label: {
                    moduleRow(icon: "doc.text", name: "Memory & context",
                              detail: (project.notes?.isEmpty == false) ? "notes" : "empty", chevron: true)
                }.buttonStyle(.plain)
                moduleRow(icon: "circle.lefthalf.filled", name: "Integrations", detail: "soon")
            }
            .padding(.vertical, ShioSpace.sm)
        }
        .background(ShioTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(String(project.name.first ?? "•").uppercased())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShioTheme.accent)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ShioTheme.accentBg))
                    Text(project.name).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ShioTheme.textPrimary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { openProject() } label: {
                    Image(systemName: "terminal").foregroundStyle(ShioTheme.accent)
                }
                .accessibilityLabel("Open terminal")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = project.name; showingRename = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button { showingAddRepo = true } label: {
                        Label("Add repo", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(ShioTheme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showingAddRepo) { AddProjectSheet(targetProject: project) }
        .sheet(isPresented: $showingNotes) { notesSheet }
        .alert("Rename project", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let n = renameText.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { project.name = n; try? context.save() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            status.refresh(ProjectStatusStore.targets(for: [project], isLocalHost: { _ in false }))
        }
    }

    // MARK: - Agent reads

    private var sessionSnaps: [(SessionStore.Session, AgentSnapshot)] {
        sessionStore.sessions(forProject: project.persistentModelID).compactMap { s in
            agents.snapshot(for: s.id).map { (s, $0) }
        }
    }
    private var needsYou: [(SessionStore.Session, AgentSnapshot)] { sessionSnaps.filter { $0.1.activity == .waiting } }
    private var working:  [(SessionStore.Session, AgentSnapshot)] { sessionSnaps.filter { $0.1.activity == .running } }

    // MARK: - Glance

    private var glanceBar: some View {
        let changes = project.sortedRepos.reduce(0) { sum, repo in
            let probe = repo.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
            return sum + GitLineFormatter.make(probe).dirty
        }
        let repoCount = project.sortedRepos.count
        return HStack(spacing: 14) {
            if changes > 0 {
                HStack(spacing: 6) { ShioStatusDot(status: .warning, size: 7)
                    Text("\(changes) changes").foregroundStyle(ShioTheme.warning) }
            }
            if !working.isEmpty {
                HStack(spacing: 6) { ShioBrailleSpinner(status: .info, size: 11)
                    Text("working").foregroundStyle(ShioTheme.info) }
            }
            if !needsYou.isEmpty {
                Text("⚑ \(needsYou.count) needs you").foregroundStyle(ShioTheme.warning)
            }
            if changes == 0 && working.isEmpty && needsYou.isEmpty {
                Text("all quiet").foregroundStyle(ShioTheme.textTertiary)
            }
            Spacer(minLength: 0)
            Text("\(repoCount) repo\(repoCount == 1 ? "" : "s")").foregroundStyle(ShioTheme.textTertiary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String, add: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title).font(ShioKitFont.label).tracking(1.5).textCase(.uppercase)
                .foregroundStyle(ShioTheme.textTertiary)
            Spacer()
            if let add {
                Button { add() } label: { Image(systemName: "plus").font(.system(size: 13)) }
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 7)
    }

    private func needsYouCard(session: SessionStore.Session, snap: AgentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(snap.agentName ?? "Agent") · \(session.displayName)")
                .font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
            if let d = snap.detail, !d.isEmpty {
                Text("\"\(d)\"").font(.system(size: 13)).foregroundStyle(ShioTheme.warning)
                    .padding(.top, 6).padding(.bottom, 11)
            } else { Color.clear.frame(height: 11) }
            ShioButton("Open terminal to answer", .secondary, icon: "terminal") { openProject() }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(ShioTheme.warningBg))
        .overlay(alignment: .leading) { Rectangle().fill(ShioTheme.warning).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private func agentRow(session: SessionStore.Session, snap: AgentSnapshot) -> some View {
        Button { openProject() } label: {
            HStack(spacing: 11) {
                ShioBrailleSpinner(status: .info, size: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.agentName ?? session.displayName)
                        .font(.system(size: 14)).foregroundStyle(ShioTheme.textPrimary)
                    if let d = snap.detail, !d.isEmpty {
                        Text(d).font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary).lineLimit(1)
                    }
                }
                Spacer()
                Text("jump ›").font(.system(size: 13)).foregroundStyle(ShioTheme.textSecondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
    }

    private func repoRow(_ repo: Repo) -> some View {
        Button { openRepo(repo) } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.name).font(.system(size: 14)).foregroundStyle(ShioTheme.textPrimary)
                    gitLine(repo)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
    }

    @ViewBuilder private func gitLine(_ repo: Repo) -> some View {
        let probe = repo.activeCheckout.flatMap { status.status(forHost: $0.host, path: $0.path)?.probe }
        let m = GitLineFormatter.make(probe)
        HStack(spacing: 9) {
            HStack(spacing: 5) {
                Text("⎇").foregroundStyle(ShioTheme.textTertiary)
                Text(m.branch).lineLimit(1).truncationMode(.middle)
            }
            .foregroundStyle(m.state == .loading || m.state == .unreachable ? ShioTheme.textTertiary : ShioTheme.textSecondary)
            if m.hasTracking {
                if m.ahead > 0 { Text("↑\(m.ahead)").foregroundStyle(ShioTheme.textSecondary) }
                if m.behind > 0 { Text("↓\(m.behind)").foregroundStyle(ShioTheme.textSecondary) }
                if m.dirty > 0 {
                    HStack(spacing: 5) { ShioStatusDot(status: .warning, size: 6)
                        Text("\(m.dirty)").foregroundStyle(ShioTheme.warning) }
                } else {
                    Text("✓").foregroundStyle(ShioTheme.success)
                }
            }
        }
        .font(.system(size: 12, design: .monospaced)).monospacedDigit()
    }

    private func moduleRow(icon: String, name: String, detail: String, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(ShioTheme.textSecondary).frame(width: 18)
            Text(name).font(.system(size: 14)).foregroundStyle(ShioTheme.textPrimary)
            Spacer()
            Text(detail).font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(ShioTheme.line).frame(height: 1) }
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
}
