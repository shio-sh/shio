import SwiftUI
import SwiftData
import PhotosUI

/// Inside a project on iPhone — the Mac rail's SHELLS/REPOS, decomposed for a
/// phone: the repos (each a standing terminal), and the project's shells. The
/// Slack-style switcher is the only thing in the header (tap the name ▾) — no
/// back button; the Home tab returns you to the overview (his calls).
struct ProjectView: View {
    @State private var project: Project
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @State private var showingSwitcher = false
    @State private var showingAddRepo = false
    @State private var showingAddProject = false
    @State private var showingTerminal = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var repoToRename: Repo?
    @State private var repoRenameText = ""
    @State private var repoNeedingHome: Repo?
    @State private var logoItem: PhotosPickerItem?
    @State private var showingLogoPicker = false
    private let sessionStore = SessionStore.shared
    private let status = ProjectStatusStore.shared

    init(project: Project) {
        _project = State(initialValue: project)
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
                        sectionHeader("repos", add: { showingAddRepo = true })
                        if project.sortedRepos.isEmpty {
                            quietHint("No repos yet — add one.")
                        } else {
                            ForEach(project.sortedRepos) { repo in repoRow(repo) }
                        }

                        if !machines.isEmpty {
                            sectionHeader("shells")
                            ForEach(machines) { host in shellRow(host) }
                        }
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
        .alert("Rename project", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let n = renameText.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { project.name = n; try? context.save() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename repo", isPresented: Binding(
            get: { repoToRename != nil }, set: { if !$0 { repoToRename = nil } })) {
            TextField("Name", text: $repoRenameText)
            Button("Save") {
                let n = repoRenameText.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty, let r = repoToRename { r.name = n; try? context.save() }
                repoToRename = nil
            }
            Button("Cancel", role: .cancel) { repoToRename = nil }
        }
        .sheet(isPresented: $showingAddRepo) { AddProjectSheet(targetProject: project) }
        .sheet(isPresented: $showingAddProject) { AddProjectSheet() }
        .fullScreenCover(isPresented: $showingTerminal) { TerminalScene() }
        .sheet(item: $repoNeedingHome) { repo in
            // Not an alert — the repair: place the repo on a machine, then
            // open it right away.
            RepoRepairSheet(repo: repo) { _ in
                if sessionStore.openOrCreate(repo: repo) != nil { showingTerminal = true }
            }
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
        .contextMenu {
            Button { renameText = project.name; showingRename = true } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button { showingLogoPicker = true } label: {
                Label(project.imageData == nil ? "Add Logo…" : "Change Logo…", systemImage: "photo")
            }
            if project.imageData != nil {
                Button(role: .destructive) {
                    project.imageData = nil
                    try? context.save()
                } label: { Label("Remove Logo", systemImage: "trash") }
            }
        }
        .photosPicker(isPresented: $showingLogoPicker, selection: $logoItem, matching: .images)
        .onChange(of: logoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let encoded = ProjectAvatar.encode(data) {
                    project.imageData = encoded
                    try? context.save()
                }
            }
        }
    }

    // MARK: repos

    private func repoRow(_ repo: Repo) -> some View {
        Button { openRepo(repo) } label: {
            HStack(spacing: 11) {
                Text("⎇").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary).frame(width: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name).font(.system(size: 14.5)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                    sub(repo)
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
        .contextMenu {
            Button { repoRenameText = repo.name; repoToRename = repo } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
    }

    private func sub(_ repo: Repo) -> some View {
        let m = GitLineFormatter.make(gitProbe(repo), stale: gitStale(repo))
        return Text("\(m.branchLabel) · \(machineLabel(repo))")
            .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
            .lineLimit(1).truncationMode(.middle)
            .opacity(m.stale ? 0.6 : 1)
    }

    private func trailingMeta(_ repo: Repo) -> some View {
        let m = GitLineFormatter.make(gitProbe(repo))
        return ShioGitStatusLine(model: m, compact: true, size: 11)
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
        return Button {
            project = p
            p.lastOpenedAt = .now
            try? context.save()
            withAnimation(.easeOut(duration: 0.12)) { showingSwitcher = false }
        } label: {
            HStack(spacing: 11) {
                projectMark(p, size: 24)
                Text(p.name).font(.system(size: 14.5)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                Spacer(minLength: 6)
                let age = shioShortAge(p.lastOpenedAt)
                if !age.isEmpty { Text(age).font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary) }
                if current { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(ShioTheme.accent) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: shared bits

    private func projectMark(_ p: Project, size: CGFloat) -> some View {
        ProjectAvatar(p, size: size)
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
    private func gitStale(_ repo: Repo) -> Bool {
        guard let c = repo.activeCheckout else { return false }
        return status.isStale(forHost: c.host, path: c.path)
    }

    private func openRepo(_ repo: Repo) {
        if sessionStore.openOrCreate(repo: repo) != nil { showingTerminal = true }
        else { repoNeedingHome = repo }
    }

    private func refresh() {
        let targets = ProjectStatusStore.targets(for: [project], isLocalHost: { _ in false })
        status.refresh(targets)
    }
}
