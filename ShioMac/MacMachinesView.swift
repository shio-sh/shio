import SwiftUI
import SwiftData

/// Machines on the Mac — master/detail in the terminal-refined language, like
/// Projects. A machines rail (This Mac + your saved remotes, each with a reach
/// dot) beside a machine detail: its connection facts and the projects checked
/// out there. Tap This Mac → a local terminal; a remote → connect over SSH.
struct MacMachinesView: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var hosts: [Host]
    @Query private var projects: [Project]
    @State private var selected: SelectedMachine? = .thisMac
    @State private var importNote: String?

    /// Pull a remote machine's existing skills into Shio (global), synced to the
    /// user's other devices and re-materialized on open.
    private func importSkills(from host: Host) {
        importNote = "Importing from \(host.name)…"
        let config = SSHClient.Configuration(
            host: host.hostname, port: host.port, username: host.username,
            authentication: .systemKeys, initialCols: 80, initialRows: 24)
        Task {
            let n = await SkillImporter.importRemote(config: config, into: context)
            importNote = n == 0 ? "No new skills found on \(host.name)." : "Imported \(n) skill\(n == 1 ? "" : "s") from \(host.name)."
        }
    }

    /// The rail selection — the self-Mac is synthetic (not always a saved Host).
    enum SelectedMachine: Hashable { case thisMac, host(PersistentIdentifier) }

    private var remotes: [Host] { hosts.filter { !MacSelfHost.isThisMac($0) } }

    var body: some View {
        VStack(spacing: 0) {
            MacCanvasHeader(title: "Machines", sub: subline) {
            } trailing: {
                ShioButton("Pair iPhone", .secondary, compact: true) { model.showingPairing = true }
                ShioButton("Add machine", .primary, compact: true) { model.showingAddHost = true }
                MacHeaderIconButton(systemImage: "sidebar.trailing", help: "Inspector (⌘I)",
                                    on: model.inspectorOpen) {
                    model.inspectorOpen.toggle()
                }
            }
            HStack(spacing: 0) {
                machineList
                Rectangle().fill(ShioTheme.line).frame(width: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ShioTheme.background)
        .sheet(isPresented: $model.showingPairing) { MacPairingView() }
        .onChange(of: hosts.count) { _, _ in ensureSelection() }
    }

    // MARK: machine list (in-canvas, quiet)

    private var subline: String {
        let n = 1 + remotes.count
        return "\(n) machine\(n == 1 ? "" : "s")"
    }

    private var machineList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                machineItem(.thisMac, name: "This Mac", sub: Self.localSubtitle, reach: .ok)
                ForEach(remotes) { host in
                    machineItem(.host(host.persistentModelID),
                                name: host.name,
                                sub: "\(host.username)@\(host.hostname) · \(host.kind.rawValue)",
                                reach: reach(host))
                    .contextMenu {
                        Button("Remove from Shio", role: .destructive) { remove(host) }
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 232)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func machineItem(_ id: SelectedMachine, name: String, sub: String, reach: Reach) -> some View {
        let isSel = selected == id
        return Button { selected = id } label: {
            HStack(spacing: 9) {
                ShioStatusDot(status: reach.status, filled: reach != .asleep)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 12.5))
                        .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textPrimary)
                        .lineLimit(1)
                    Text(sub).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSel ? ShioTheme.accentBg : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: detail

    @ViewBuilder private var detail: some View {
        switch selected ?? .thisMac {
        case .thisMac:
            machineDetail(name: "This Mac", reachable: true,
                          rows: [("host", Self.localSubtitle),
                                 ("kind", "this device · self-host"),
                                 ("last connected", "now")],
                          openTitle: "Open terminal", open: { model.newLocalTab() },
                          host: nil)
        case .host(let id):
            if let host = hosts.first(where: { $0.persistentModelID == id }) {
                machineDetail(name: host.name, reachable: reach(host) != .asleep,
                              rows: [("host", "\(host.username)@\(host.hostname)"),
                                     ("port", "\(host.port)"),
                                     ("kind", host.kind.rawValue),
                                     ("last connected", shioShortAge(host.lastConnectedAt).isEmpty ? "never" : shioShortAge(host.lastConnectedAt))],
                              openTitle: "Connect", open: { connect(host) },
                              host: host)
            } else { Color.clear }
        }
    }

    private func machineDetail(name: String, reachable: Bool, rows: [(String, String)],
                               openTitle: String, open: @escaping () -> Void, host: Host?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(ShioTheme.textPrimary)
                    ShioStatusDot(status: reachable ? .success : .neutral)
                    Text(reachable ? "reachable" : "asleep")
                        .font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
                    Spacer()
                    ShioButton(openTitle, .primary, icon: "terminal", compact: true, action: open)
                    if let host {
                        ShioButton("Import skills", .ghost, icon: "square.and.arrow.down", compact: true) {
                            importSkills(from: host)
                        }
                        ShioButton("Remove", .secondary, compact: true) { remove(host) }
                    }
                }
                if let importNote {
                    Text(importNote).font(.system(size: 11)).foregroundStyle(ShioTheme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.0) { kv in
                        HStack(spacing: 0) {
                            Text(kv.0).font(.system(size: 12.5)).foregroundStyle(ShioTheme.textSecondary).frame(width: 130, alignment: .leading)
                            Text(kv.1).font(.system(size: 12.5)).foregroundStyle(ShioTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.vertical, 7)
                    }
                }
                projectsHere(host: host)
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    @ViewBuilder private func projectsHere(host: Host?) -> some View {
        let here = projectsOn(host: host)
        if !here.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ShioSectionHeader("projects here").padding(.bottom, 4)
                ForEach(here) { project in
                    HStack(spacing: 10) {
                        Text("›").foregroundStyle(ShioTheme.textTertiary)
                        Text(project.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary)
                        Spacer()
                        let n = project.sortedRepos.count
                        Text("\(n) repo\(n == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(ShioTheme.textTertiary)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 9)
                }
            }
        }
    }

    // MARK: data

    private func projectsOn(host: Host?) -> [Project] {
        projects.filter { project in
            project.allCheckouts.contains { c in
                if let host { return c.host?.persistentModelID == host.persistentModelID }
                return c.host.map(MacSelfHost.isThisMac) ?? true   // self-Mac: local checkouts
            }
        }
        .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

    private func connect(_ host: Host) {
        host.lastConnectedAt = .now
        try? context.save()
        model.connect(to: host)
    }

    private func remove(_ host: Host) {
        if selected == .host(host.persistentModelID) { selected = .thisMac }
        // Drop the TOFU pin too — "remove the host and re-add it" is the
        // documented recovery for a changed host key, so removal has to
        // actually clear the pin.
        ShioKnownHosts.forget("\(host.hostname):\(host.port)")
        ModelCascade.delete(host: host, context: context)
        try? context.save()
    }

    private func ensureSelection() {
        if case .host(let id) = selected, !hosts.contains(where: { $0.persistentModelID == id }) {
            selected = .thisMac
        }
    }

    enum Reach { case ok, asleep
        var status: ShioStatus { self == .ok ? .success : .neutral }
    }
    /// No live probe yet — treat a machine not connected in 3 days as asleep.
    private func reach(_ host: Host) -> Reach {
        guard let last = host.lastConnectedAt else { return .asleep }
        return last.timeIntervalSinceNow > -3 * 24 * 3600 ? .ok : .asleep
    }

    private static var localSubtitle: String {
        let host = ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
        return "\(NSUserName())@\(host)"
    }
}
