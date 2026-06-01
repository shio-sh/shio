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

struct MacShell: View {
    @Bindable var model: MacTerminalModel

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
        case .agents:   placeholder("Agents", "sparkles", "Agents across your sessions show up here.")
        case .files:    MacFilesPane()
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
    @State private var showingAddProject = false

    var body: some View {
        Group {
            if projects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.fill").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No projects yet").font(.system(.title2, design: .monospaced))
                    Text("A repo on this Mac or any machine — open a folder, or clone from Git.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add a project") { showingAddProject = true }
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
                        Button { showingAddProject = true } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddProject) { MacAddProjectForm(model: model) }
    }

    private func subtitle(_ project: Project) -> String {
        if let host = project.host { return "\(host.name) · \(project.path)" }
        return "This Mac · \(project.path)"
    }

    private func open(_ project: Project) {
        project.lastOpenedAt = .now
        try? context.save()
        model.open(project: project)
    }
}

/// Hosts list (SwiftData-backed): add machines, connect, quick-connect.
private struct HostsPane: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var hosts: [Host]
    var body: some View {
        Group {
            if hosts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "desktopcomputer").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No machines yet").font(.system(.title2, design: .monospaced))
                    Text("Add a server or device you own, then tap it to connect.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Add a machine") { model.showingAddHost = true }
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
                .navigationTitle("Machines")
                .toolbar {
                    ToolbarItem {
                        Button { model.showingAddHost = true } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
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
