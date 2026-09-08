import SwiftUI
import SwiftData

/// What fills the center of the window. The rail is permanent (collapse aside);
/// the canvas is what a rail row landed you on: the team's dashboard, a
/// terminal (repo or loose shell), or the Machines/Files utilities.
enum MacCanvas: Equatable {
    case dashboard
    case terminal
    case machines
    case files
}

/// The Shio window: ONE rail (project switcher + shells/repos + utility
/// rows), a center canvas, and window-level chrome — the traffic lights float
/// natively, the ◧ rail toggle sits FIXED beside them (same spot open or
/// collapsed, ⌘\), and the project switcher's menu overlays the rail rather
/// than pushing it.
struct MacShell: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var projects: [Project]

    /// First run only, and only with nothing to show. Someone whose projects
    /// arrived from another device over iCloud has already met Shio, and
    /// "start with a folder" would be wrong in front of three of them.
    @State private var showingOnboarding =
        !UserDefaults.standard.bool(forKey: MacOnboarding.completedKey)

    /// Set by Help ▸ Show Welcome, so the pass can be re-read after first run
    /// even once projects exist.
    @State private var replaying = false

    private var onboarding: Bool {
        (showingOnboarding && projects.isEmpty) || replaying
    }

    /// The shell is ALWAYS the window's root view and onboarding covers it,
    /// rather than the two swapping places. Returning a different view tree
    /// from the root of the WindowGroup makes SwiftUI tear the window down and
    /// rebuild it: finishing the pass closed the window instead of revealing
    /// the app. Overlaying keeps one stable root, and lets the shell's launch
    /// tasks (self-host registration, migration, status) run underneath while
    /// the pass is still on screen.
    var body: some View {
        shell
            .overlay {
                if onboarding {
                    MacOnboarding(
                        onOpenFolder:     { model.showingAddProject = true },
                        onCloneFromLink:  { model.showingAddProject = true },
                        onConnectMachine: { model.showingAddHost = true },
                        onFinish: { showingOnboarding = false; replaying = false }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: onboarding)
            .onReceive(NotificationCenter.default.publisher(for: .shioShowWelcome)) { _ in
                replaying = true
            }
    }

    private var shell: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if !model.sidebarCollapsed {
                    MacRail(model: model)
                    MacSidebarDivider()
                }
                center
                    // Collapsed rail = the lights + toggle float over the
                    // canvas; headers clear that strip instead of running
                    // under it.
                    .environment(\.shioHeaderLeadingInset,
                                 model.sidebarCollapsed ? MacChrome.lightsClearance : 0)
                    // Nothing the center draws may ever cross a divider.
                    .clipped()
                if model.inspectorOpen {
                    MacSidebarDivider()
                    MacInspector(model: model)
                }
            }

            // While the rail is open the toggle lives in its switcher row;
            // collapsed, it floats beside the lights on their centerline.
            if model.sidebarCollapsed {
                MacRailToggleButton(model: model)
                    .padding(.leading, 84)
                    .padding(.top, 2)   // centered on the compact lights row
            }

            if model.showingProjectMenu, !model.sidebarCollapsed {
                // Click-away catcher under the menu.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.showingProjectMenu = false }
                MacProjectMenu(model: model)
                    .padding(.leading, 10)
                    .padding(.top, 86)
            }
        }
        .ignoresSafeArea(edges: .top)
        // NO window toolbar, ever. The Slack-position lights were tried twice:
        // assigning an NSToolbar crashes SwiftUI's toolbar bridge, and a
        // SwiftUI toolbar renders Liquid Glass artifacts AND hit-tests across
        // the whole top strip, eating the canvas headers' clicks. The compact
        // system lights position is the price of a fully ours top edge.
        .sheet(isPresented: $model.showingAddHost) {
            MacAddHostForm(model: model)
        }
        .sheet(isPresented: $model.showingAddProject) {
            MacAddProjectForm(model: model)
        }
        .sheet(item: $model.addRepoToProject) { project in
            MacAddProjectForm(model: model, targetProject: project)
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
            // Restore last run's tabs so SHELLS/REPOS rows light up without
            // having to visit the terminal first.
            model.ensureRestored()
            refreshStatus()
        }
        // Hold off sleep while a device is attached over SSH.
        .task { PowerKeeper.shared.start() }
        // Release the renderer of terminals idle in the background —
        // tmux keeps the session, so reopening reattaches losslessly.
        .task { model.startHibernator() }
        // The rail is always on screen now — keep its git state warm app-wide.
        // warmOnly so it never wakes a sleeping remote.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                ProjectStatusStore.shared.refresh(ProjectStatusStore.targets(
                    for: projects, isLocalHost: MacSelfHost.isThisMac, warmOnly: true))
            }
        }
        .onChange(of: model.selectedProject?.persistentModelID) { _, _ in
            refreshStatus()
        }
        // Re-detect the reachable address whenever the app becomes active, so
        // turning Tailscale on/off (or a network change) updates the synced
        // address without needing to relaunch — cross-network self-heals.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { MacSelfHost.ensure(in: context) }
        }
    }

    @ViewBuilder
    private var center: some View {
        switch model.canvas {
        case .dashboard:    MacDashboardCanvas(model: model)
        case .terminal:     TerminalWorkspaceView(model: model)
        case .machines:     MacMachinesView(model: model)
        case .files:        MacFilesPane(model: model)
        }
    }

    private func refreshStatus() {
        let targets = ProjectStatusStore.targets(for: projects, isLocalHost: MacSelfHost.isThisMac)
        ProjectStatusStore.shared.refresh(targets)
    }
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
        .background(ShioTheme.hover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ShioTheme.line, lineWidth: 1))
        .padding(.horizontal, 12).padding(.top, 10)
        .onAppear { focused = true }
    }

    private func close() { model.showingSearch = false; model.searchQuery = "" }
}

/// Add a machine and connect to it. One sheet: saves the `Host` for next time
/// AND opens a shell now. The password is optional — leave it empty to use
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
                ShioButton("Add & Connect", .primary, compact: true) { addAndConnect() }
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
