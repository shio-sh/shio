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
    @AppStorage("shio.skills.crossAppExplained") private var skillsExplained = false
    @AppStorage(SkillMaterializer.syncEnabledKey) private var skillSyncEnabled = true
    @State private var showSkillsExplainer = false

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
        case .projects: MacProjectsView(model: model)
        case .hosts:    MacMachinesView(model: model)
        case .files:    MacFilesPane(model: model)
        }
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

    private func placeholder(_ title: String, _ icon: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.system(.title2, design: .monospaced))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12).padding(.top, 10)
        .onAppear { focused = true }
    }

    private func close() { model.showingSearch = false; model.searchQuery = "" }
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
