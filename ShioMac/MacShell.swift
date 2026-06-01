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
struct MacShell: View {
    @Bindable var model: MacTerminalModel

    enum Section: String, CaseIterable, Identifiable {
        case terminal = "Terminal"
        case projects = "Projects"
        case hosts = "Hosts"
        case agents = "Agents"
        case files = "Files"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .terminal: return "terminal"
            case .projects: return "folder.fill"
            case .hosts: return "desktopcomputer"
            case .agents: return "sparkles"
            case .files: return "tray.full.fill"
            }
        }
    }

    @State private var selection: Section? = .terminal

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
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
        .sheet(isPresented: $model.showingConnect) {
            ConnectSheet { host, port, user, password in
                let session = MacSSHSession(host: host, port: port, username: user, password: password)
                model.active = .ssh(session)
                Task { await session.connect() }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let active = model.active {
            // The active session takes the detail pane (tabs/splits later).
            ZStack(alignment: .topTrailing) {
                GhosttySurfaceHost(surface: active.surface).id(active.id)
                Button { model.closeActive() } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        } else {
            switch selection ?? .terminal {
            case .terminal: GhosttyMacTerminal()
            case .projects: ProjectsPane(model: model)
            case .hosts:    HostsPane(model: model)
            case .agents:   placeholder("Agents", "sparkles", "Agents across your sessions show up here.")
            case .files:    placeholder("Files", "tray.full.fill", "Browse your machines over SFTP here.")
            }
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

    var body: some View {
        Group {
            if projects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.fill").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No projects yet").font(.system(.title2, design: .monospaced))
                    Text("A repo on a machine you own. Syncs with your iPhone.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Add a folder on this Mac") { addLocalProject() }
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(projects) { project in
                        Button { open(project) } label: {
                            VStack(alignment: .leading) {
                                Text(project.name).font(.body)
                                Text(subtitle(project))
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(projects[i]) }
                        try? context.save()
                    }
                }
                .navigationTitle("Projects")
                .toolbar {
                    ToolbarItem {
                        Button { addLocalProject() } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
    }

    private func subtitle(_ project: Project) -> String {
        if let host = project.host { return "\(host.name) · \(project.path)" }
        return "This Mac · \(project.path)"
    }

    private func open(_ project: Project) {
        project.lastOpenedAt = .now
        try? context.save()
        if let host = project.host {
            // Remote project: SSH to the host, attach `shio-<project>` in the
            // repo dir (cloning first if it was created from a git URL).
            let resume = TmuxResume.resumeCommand(
                named: "shio-\(TmuxResume.scrubName(project.name))",
                startDir: project.path,
                cloneURL: project.cloneURL
            )
            let session = MacSSHSession(host: host.hostname, port: host.port,
                                        username: host.username, password: nil,
                                        resumeCommand: resume)
            model.active = .ssh(session)
            Task { await session.connect() }
        } else {
            // Local project on this Mac: a `.local` invisible-tmux surface.
            model.active = .project(MacLocalProjectSession(project: project))
        }
    }

    /// Pick a folder on this Mac and save it as a local project.
    private func addLocalProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Pick a repo or folder on this Mac to work on in Shio."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let project = Project(name: url.lastPathComponent, path: url.path, host: nil)
        context.insert(project)
        try? context.save()
        open(project)
    }
}

/// Hosts list (SwiftData-backed): add machines, connect, quick-connect.
private struct HostsPane: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var hosts: [Host]
    @State private var showingAddHost = false

    var body: some View {
        Group {
            if hosts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "desktopcomputer").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No machines yet").font(.system(.title2, design: .monospaced))
                    Text("Add a server, or quick-connect to one.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Add a machine") { showingAddHost = true }
                        Button("Quick connect…") { model.showingConnect = true }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(hosts) { host in
                        Button { open(host) } label: {
                            VStack(alignment: .leading) {
                                Text(host.name).font(.body)
                                Text("\(host.username)@\(host.hostname)")
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(hosts[i]) }
                        try? context.save()
                    }
                }
                .navigationTitle("Hosts")
                .toolbar {
                    ToolbarItem {
                        Button { showingAddHost = true } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddHost) { MacAddHostForm() }
    }

    private func open(host: Host) {
        host.lastConnectedAt = .now
        try? context.save()
        let session = MacSSHSession(host: host.hostname, port: host.port,
                                    username: host.username, password: nil)
        model.active = .ssh(session)
        Task { await session.connect() }
    }
    // Trailing-closure label needs an argument label match; bridge it.
    private func open(_ host: Host) { open(host: host) }
}

/// Add a saved machine. (Full pairing / Pro-mode options come with the host
/// detail screen; this is the core add.)
private struct MacAddHostForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var hostname = ""
    @State private var user = NSUserName()
    @State private var port = "22"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a machine")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. My Server"))
                TextField("Host", text: $hostname, prompt: Text("hostname or IP"))
                TextField("User", text: $user)
                TextField("Port", text: $port)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(hostname.trimmingCharacters(in: .whitespaces).isEmpty || user.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func add() {
        let cleanHost = hostname.trimmingCharacters(in: .whitespaces)
        let host = Host(
            name: name.isEmpty ? cleanHost : name,
            hostname: cleanHost,
            port: Int(port) ?? 22,
            username: user,
            kind: .directSSH
        )
        context.insert(host)
        try? context.save()
        dismiss()
    }
}
