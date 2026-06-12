import SwiftUI
import SwiftData

/// What fills the center of the window. The rail is permanent (collapse aside);
/// the canvas is what a rail row landed you on: the team's dashboard, a
/// conversation's terminal, or the Machines/Files utilities.
enum MacCanvas: Equatable {
    case dashboard
    case conversation
    case machines
    case files
}

/// The Shio window: ONE rail (project switcher + agents/shells/repos + utility
/// rows), a center canvas, and window-level chrome — the traffic lights float
/// natively, the ◧ rail toggle sits FIXED beside them (same spot open or
/// collapsed, ⌘\), and the project switcher's menu overlays the rail rather
/// than pushing it.
struct MacShell: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var projects: [Project]
    @AppStorage("shio.skills.crossAppExplained") private var skillsExplained = false
    @AppStorage(SkillMaterializer.syncEnabledKey) private var skillSyncEnabled = true
    @State private var showSkillsExplainer = false

    var body: some View {
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
                    .padding(.leading, 100)
                    .padding(.top, 12)
            }

            if model.showingProjectMenu, !model.sidebarCollapsed {
                // Click-away catcher under the menu.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.showingProjectMenu = false }
                MacProjectMenu(model: model)
                    .padding(.leading, 10)
                    .padding(.top, 90)
            }
        }
        .ignoresSafeArea(edges: .top)
        // Slack-style titlebar: an invisible toolbar item makes the window
        // carry a (transparent) unified toolbar, which moves the traffic
        // lights to the relaxed position. Declared through SwiftUI so IT owns
        // the NSToolbar — assigning our own crashed its toolbar bridge
        // (KVO removeObserver on a toolbar it never registered on).
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(isPresented: $model.showingAddHost) {
            MacAddHostForm(model: model)
        }
        .sheet(isPresented: $model.showingAddProject) {
            MacAddProjectForm(model: model)
        }
        .sheet(item: $model.addRepoToProject) { project in
            MacAddProjectForm(model: model, targetProject: project)
        }
        // Explain BEFORE the first cross-app write why macOS is about to ask to
        // "access data from other apps" — Shio is syncing your skills into the
        // agents' own folders. (The system prompt itself isn't customizable.)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A disable/edit made on another device while this Mac app was
            // running reconciles on the next activation, not the next launch.
            maybeSyncSkills()
        }
        .alert("Sync your skills to your coding agents?", isPresented: $showSkillsExplainer) {
            Button("Sync skills") { skillsExplained = true; SkillMaterializer.shared.scheduleGlobalSync() }
            Button("Don't sync", role: .cancel) { skillsExplained = true; skillSyncEnabled = false }
        } message: {
            Text("Shio writes your skills into the folders your coding agents read — Claude Code (~/.claude), Cursor, and Codex — so they follow your rules automatically. macOS will then ask permission to access those apps' folders; that's expected. You can change this anytime in Settings → Skills.")
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
            maybeSyncSkills()
            // Restore last run's tabs so SHELLS/REPOS rows light up without
            // having to visit the terminal first.
            model.ensureRestored()
            refreshStatus()
        }
        // Watch local tmux sessions so a repo row lights up when its agent
        // needs you — even though ghostty owns the local PTY.
        .task { MacProjectAgentMonitor.shared.start() }
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
        case .conversation: TerminalWorkspaceView(model: model)
        case .machines:     MacMachinesView(model: model)
        case .files:        MacFilesPane(model: model)
        }
    }

    private func refreshStatus() {
        let targets = ProjectStatusStore.targets(for: projects, isLocalHost: MacSelfHost.isThisMac)
        ProjectStatusStore.shared.refresh(targets)
        ProjectStatusStore.shared.refreshPRs(targets)
    }

    /// Sync global skills into the agents' folders — but only when enabled and
    /// there's something to write, and explain it the first time (so the macOS
    /// "data from other apps" prompt isn't a surprise).
    private func maybeSyncSkills() {
        // hasGlobalWork, not "has enabled globals": a disable/delete made on
        // another device still has to clean THIS Mac's folders.
        guard skillSyncEnabled, SkillMaterializer.shared.hasGlobalWork() else { return }
        if skillsExplained { SkillMaterializer.shared.scheduleGlobalSync() }
        else { showSkillsExplainer = true }
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
