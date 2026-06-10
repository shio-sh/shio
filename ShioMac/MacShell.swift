import SwiftUI
import SwiftData

/// The Shio organization shell on macOS: a NavigationSplitView with the
/// Projects / Hosts / Agents / Files sidebar and a terminal/detail pane —
/// parity with the iOS 4-tab IA, in the native Mac idiom.
///
/// This slice establishes the structure (so the Mac reads as Shio, not a bare
/// terminal) backed by the shared SwiftData models. Opening project/host
/// sessions, iCloud sync, Agents/Files content, and the proper chrome fill in
/// next.
/// Sidebar sections (top-level so `MacTerminalModel` can drive the selection).
enum MacSection: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case projects = "Projects"
    case hosts = "Machines"
    case files = "Files"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .terminal: return "terminal"
        case .projects: return "folder.fill"
        case .hosts: return "desktopcomputer"
        case .files: return "tray.full.fill"
        }
    }
}

struct MacShell: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            List(MacSection.allCases, selection: sectionBinding) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
            .safeAreaInset(edge: .bottom) {
                Text("塩 shio")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        } detail: {
            detail
        }
        .sheet(isPresented: $model.showingAddHost) {
            MacAddHostForm(model: model)
        }
        .overlay {
            if model.showingCommandPalette {
                CommandPaletteContainer(model: model)
            }
        }
        // Register This Mac as a synced Machine so its local projects are
        // reachable (continuity) and it appears on the user's other devices.
        .task {
            MacSelfHost.ensure(in: context)
            // Project-first migration: backfill a ProjectCheckout per legacy
            // single-host project. Idempotent + safe to run every launch.
            ProjectMigration.run(in: context)
        }
        // Watch local tmux sessions so a project row lights up when its agent
        // needs you — even though ghostty owns the local PTY.
        .task { MacProjectAgentMonitor.shared.start() }
        // Re-detect the reachable address whenever the app becomes active, so
        // turning Tailscale on/off (or a network change) updates the synced
        // address without needing to relaunch — cross-network self-heals.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { MacSelfHost.ensure(in: context) }
        }
    }

    /// List wants an optional selection binding; the model's section is always
    /// set, so bridge it (ignore deselection).
    private var sectionBinding: Binding<MacSection?> {
        Binding(get: { model.section }, set: { if let v = $0 { model.section = v } })
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .terminal: TerminalWorkspaceView(model: model)
        case .projects: ProjectsPane(model: model)
        case .hosts:    HostsPane(model: model)
        case .files:    MacFilesPane(model: model)
        }
    }

    private func placeholder(_ title: String, _ icon: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.system(.title2, design: .monospaced))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Projects list (SwiftData-backed). Opening a project attaches its
/// invisible-tmux session: local projects (a folder on this Mac) via the
/// `.local` ghostty backend; projects on a host over SSH.
private struct ProjectsPane: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @State private var agents = MacProjectAgentMonitor.shared

    private var filtered: [Project] {
        let q = model.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return projects }
        return projects.filter {
            $0.name.lowercased().contains(q)
                || $0.path.lowercased().contains(q)
                || ($0.host?.name.lowercased().contains(q) ?? false)
        }
    }

    private let status = ProjectStatusStore.shared

    /// Needs-you first, then running, then most-recently-opened.
    private var sortedFiltered: [Project] {
        filtered.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (a.lastOpenedAt ?? .distantPast) > (b.lastOpenedAt ?? .distantPast)
        }
    }
    private func rank(_ p: Project) -> Int {
        switch localAgentActivity(p) {
        case .waiting: return 0
        case .running: return 1
        default:       return 2
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.showingSearch {
                SectionSearchField(model: model, placeholder: "Search projects")
            }
            if projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(sortedFiltered) { project in
                            MacProjectCard(
                                name: project.name,
                                machines: machinesText(project),
                                age: shioShortAge(project.lastOpenedAt),
                                git: gitProbe(project),
                                agentActivity: localAgentActivity(project),
                                open: { open(project) },
                                remove: { remove(project) }
                            )
                        }
                    }
                    .padding(12)
                    if filtered.isEmpty {
                        Text("No matches")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .navigationTitle("Projects")
                .toolbar {
                    ToolbarItem {
                        Button { model.showingAddProject = true } label: { Image(systemName: "plus") }
                    }
                }
                .onAppear { refreshStatus() }
            }
        }
        .sheet(isPresented: $model.showingAddProject) { MacAddProjectForm(model: model) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("塩").font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("No projects yet").font(.system(.title2, design: .monospaced))
            Text("A repo on this Mac or any machine — open a folder, or clone from Git.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add a project") { model.showingAddProject = true }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func remove(_ project: Project) {
        context.delete(project)
        try? context.save()
    }

    private func refreshStatus() {
        status.refresh(ProjectStatusStore.targets(for: projects, isLocalHost: MacSelfHost.isThisMac))
    }

    private func gitProbe(_ project: Project) -> GitProbe? {
        guard let c = project.activeCheckout else { return nil }
        return status.status(forHost: c.host, path: c.path)?.probe
    }

    private func machinesText(_ project: Project) -> String {
        let names = project.allCheckouts.map { c -> String in
            guard let h = c.host else { return "this mac" }
            return MacSelfHost.isThisMac(h) ? "this mac" : h.name
        }
        var seen = Set<String>(); var unique: [String] = []
        for n in names where !seen.contains(n) { seen.insert(n); unique.append(n) }
        return unique.isEmpty ? "this mac" : unique.joined(separator: " · ")
    }

    /// The tmux capture-pane monitor only sees THIS Mac, so only trust it for a
    /// project that has a checkout here — else a same-named remote project would
    /// borrow a local agent's state.
    private func localAgentActivity(_ project: Project) -> AgentActivity {
        let checkouts = project.allCheckouts
        let hasLocal = checkouts.isEmpty || checkouts.contains { $0.host.map(MacSelfHost.isThisMac) ?? true }
        guard hasLocal else { return .none }
        return agents.snapshot(forProjectNamed: project.name)?.activity ?? .none
    }

    private func open(_ project: Project) {
        project.lastOpenedAt = .now
        try? context.save()
        model.open(project: project)
    }
}

/// One project card in the Mac command center — monospace dialect, git + agent
/// glance, a quiet amber edge when an agent needs you.
private struct MacProjectCard: View {
    let name: String
    let machines: String
    let age: String
    let git: GitProbe?
    let agentActivity: AgentActivity
    let open: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    private var needsYou: Bool { agentActivity == .waiting }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(needsYou ? MacInk.amber : Color.clear)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(name).font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
                        Spacer()
                        if !age.isEmpty {
                            Text(age).font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary).monospacedDigit()
                        }
                    }
                    Text(machines)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    gitLine
                    if let agentText { agentLine(agentText) }
                }
                .padding(10)
            }
            .background(hovering ? Color.primary.opacity(0.07) : Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove from Shio", role: .destructive, action: remove)
        }
    }

    @ViewBuilder private var gitLine: some View {
        let m = GitLineFormatter.make(git)
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                Text(m.branch).lineLimit(1).truncationMode(.middle)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(m.state == .loading || m.state == .unreachable ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))

            if m.hasTracking {
                if m.ahead > 0 { tag("↑\(m.ahead)", .secondary) }
                if m.behind > 0 { tag("↓\(m.behind)", .secondary) }
                if m.dirty > 0 { tag("●\(m.dirty)", nil, color: MacInk.amber) }
                else { tag("clean", nil, color: MacInk.green) }
            }
            Spacer(minLength: 0)
        }
    }

    private func tag(_ text: String, _ style: HierarchicalShapeStyle?, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color ?? Color.secondary)
    }

    private var agentText: String? {
        switch agentActivity {
        case .waiting:  return "needs you"
        case .running:  return "working…"
        case .finished: return "finished"
        case .none:     return nil
        }
    }

    @ViewBuilder private func agentLine(_ text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(agentActivity == .waiting ? MacInk.amber
                      : (agentActivity == .finished ? MacInk.green : MacInk.info))
                .frame(width: 6, height: 6)
            Text(text).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

/// Machines list. This Mac is a first-class machine (tap → local terminal);
/// saved remote machines (SwiftData) connect over SSH.
private struct HostsPane: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var hosts: [Host]

    private var query: String { model.searchQuery.trimmingCharacters(in: .whitespaces).lowercased() }
    private var filteredHosts: [Host] {
        // Exclude this Mac's own self-Host — it's shown as "This Mac" above.
        let remote = hosts.filter { !MacSelfHost.isThisMac($0) }
        guard !query.isEmpty else { return remote }
        return remote.filter {
            $0.name.lowercased().contains(query)
                || $0.hostname.lowercased().contains(query)
                || $0.username.lowercased().contains(query)
        }
    }
    private var showThisMac: Bool {
        query.isEmpty || "this mac".contains(query) || Self.localSubtitle.lowercased().contains(query)
    }
    /// Remote machines = all hosts minus this Mac's own self-host.
    private var remoteCount: Int { hosts.filter { !MacSelfHost.isThisMac($0) }.count }

    var body: some View {
        VStack(spacing: 0) {
            if model.showingSearch {
                SectionSearchField(model: model, placeholder: "Search machines")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if showThisMac {
                        PromptSectionHeader(title: "This Mac")
                        // 塩 marks your own machine — tap to open a local terminal.
                        PromptRow(name: "This Mac", detail: Self.localSubtitle,
                                  pinnedGlyph: "塩") {
                            model.newLocalTab()
                        }
                    }
                    PromptSectionHeader(title: "Remote")
                    if remoteCount == 0 {
                        Text("Add a server or device you own, then tap it to connect.")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 4)
                    } else if filteredHosts.isEmpty {
                        Text("No matches")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 4)
                    } else {
                        ForEach(filteredHosts) { host in
                            PromptRow(name: host.name,
                                      detail: "\(host.username)@\(host.hostname)",
                                      age: shioShortAge(host.lastConnectedAt)) {
                                open(host)
                            }
                            .contextMenu {
                                Button("Remove from Shio", role: .destructive) {
                                    context.delete(host)
                                    try? context.save()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .navigationTitle("Machines")
        .toolbar {
            ToolbarItem {
                Button { model.showingPairing = true } label: { Image(systemName: "qrcode") }
                    .help("Pair your iPhone")
            }
            ToolbarItem {
                Button { model.showingAddHost = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $model.showingPairing) { MacPairingView() }
    }

    /// `amrith@Amriths-MacBook-Pro` — the local account + computer name.
    private static var localSubtitle: String {
        let host = ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
        return "\(NSUserName())@\(host)"
    }

    /// Tap a saved host to (re)connect with the Shio key.
    private func open(host: Host) {
        host.lastConnectedAt = .now
        try? context.save()
        model.connect(to: host)
    }
    // Trailing-closure label needs an argument label match; bridge it.
    private func open(_ host: Host) { open(host: host) }
}

/// Reusable context-aware ⌘F filter field shown at the top of a list section.
/// Bound to the shared `model.searchQuery`; esc clears + closes.
struct SectionSearchField: View {
    @Bindable var model: MacTerminalModel
    var placeholder: String
    var onSubmit: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(placeholder, text: $model.searchQuery)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { onSubmit?() }
                .onKeyPress(.escape) { close(); return .handled }
            if !model.searchQuery.isEmpty {
                Button { model.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12).padding(.top, 10)
        .onAppear { focused = true }
    }

    private func close() { model.showingSearch = false; model.searchQuery = "" }
}

/// A machine row: icon, name, monospaced subtitle.
private struct MacMachineRow: View {
    let icon: String
    let name: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 2)
    }
}

/// Add a machine and connect to it. One sheet: saves the `Host` for next time
/// AND opens a session now. The password is optional — leave it empty to use
/// your Shio key (once the host has it authorized); it's used for this first
/// connect only and never stored. (Full pairing / Pro-mode options come with
/// the host detail screen.)
private struct MacAddHostForm: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var hostname = ""
    @State private var user = NSUserName()
    @State private var port = "22"
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a machine")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. My Server"))
                TextField("Host", text: $hostname, prompt: Text("hostname or IP"))
                TextField("User", text: $user)
                TextField("Port", text: $port)
                SecureField("Password", text: $password, prompt: Text("optional — leave empty to use your Shio key"))
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add & Connect") { addAndConnect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(hostname.trimmingCharacters(in: .whitespaces).isEmpty || user.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func addAndConnect() {
        let cleanHost = hostname.trimmingCharacters(in: .whitespaces)
        let host = Host(
            name: name.isEmpty ? cleanHost : name,
            hostname: cleanHost,
            port: Int(port) ?? 22,
            username: user,
            kind: .directSSH
        )
        context.insert(host)
        host.lastConnectedAt = .now
        try? context.save()
        model.connect(to: host, password: password.isEmpty ? nil : password)
        dismiss()
    }
}
