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
                model.session = session
                Task { await session.connect() }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = model.session {
            // An active SSH session takes the detail pane (tabs/splits later).
            ZStack(alignment: .topTrailing) {
                GhosttySurfaceHost(surface: session.surface).id(session.id)
                Button {
                    let s = model.session; model.session = nil
                    Task { await s?.stop() }
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        } else {
            switch selection ?? .terminal {
            case .terminal: GhosttyMacTerminal()
            case .projects: ProjectsPane()
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

/// Projects list (SwiftData-backed). Opening a project session lands next.
private struct ProjectsPane: View {
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    var body: some View {
        if projects.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "folder.fill").font(.largeTitle).foregroundStyle(.secondary)
                Text("No projects yet").font(.system(.title2, design: .monospaced))
                Text("A repo on a machine you own. Syncs with your iPhone.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(projects) { project in
                VStack(alignment: .leading) {
                    Text(project.name).font(.body)
                    Text(project.host?.name ?? "No machine")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Projects")
        }
    }
}

/// Hosts list (SwiftData-backed) + a quick connect.
private struct HostsPane: View {
    @Bindable var model: MacTerminalModel
    @Query(sort: \Host.name) private var hosts: [Host]
    var body: some View {
        VStack(spacing: 12) {
            if hosts.isEmpty {
                Image(systemName: "desktopcomputer").font(.largeTitle).foregroundStyle(.secondary)
                Text("No machines yet").font(.system(.title2, design: .monospaced))
                Text("Connect to a server, or pair this Mac with your phone.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                List(hosts) { host in
                    VStack(alignment: .leading) {
                        Text(host.name).font(.body)
                        Text("\(host.username)@\(host.hostname)")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Connect to host…") { model.showingConnect = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
