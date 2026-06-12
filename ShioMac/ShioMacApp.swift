import SwiftUI

/// Shio for Mac — a native AppKit/SwiftUI app hosting libghostty (NOT Mac
/// Catalyst). Shares the platform-agnostic core (SSH, profiles, keys, agents,
/// design tokens) with the iOS app via target membership in project.yml.
///
/// Current state: a working native local terminal, plus a minimal SSH session
/// path that attaches the same tmux session the phone uses (continuity). The
/// full Projects/Hosts/Agents/Files org + iCloud sync + the proper chrome land
/// in the next milestones.
@main
struct ShioMacApp: App {
    @State private var model = MacTerminalModel()
    // RC3 away-watcher: keeps the agent monitor alive (and the away-signal
    // firing) when the window is closed, if the menu-bar watcher is enabled.
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MacShell(model: model)
                .modelContainer(ShioModelContainer.shared)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            // Copy/Paste come from SwiftUI's default Edit menu — those route
            // copy:/paste: to the focused GhosttyMacSurface via the responder
            // chain, so no custom Edit items are needed.
            CommandGroup(after: .newItem) {
                Button("New Tab") { model.newLocalTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Command Palette…") { model.showingCommandPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Refresh") {
                    Task { await SyncRefresh.run(ShioModelContainer.shared.mainContext) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Session") {
                Button("Add Machine…") { model.showingAddHost = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            // Jump straight to a sidebar section. Mnemonic ⌘⇧+letter
            // (T/P/M/F) — plain ⌘+letter is taken by Tab/Find/Minimize/SelectAll.
            CommandMenu("Go") {
                Button("Terminal") { model.show(.terminal) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Projects") { model.show(.projects) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Machines") { model.show(.hosts) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Files") { model.show(.files) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Tabs") {
                Button("New Tab") { model.newLocalTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Close Pane / Tab") { model.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: .command)
                Divider()
                Button("Next Tab") { model.selectAdjacentTab(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { model.selectAdjacentTab(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                ForEach(1...9, id: \.self) { n in
                    Button("Select Tab \(n)") { model.selectTab(at: n - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") { model.showFind() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find Next") { model.findNext() }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { model.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandMenu("Terminal") {
                Button("Split Right") { model.splitFocused(.horizontal) }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Split Down") { model.splitFocused(.vertical) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                // ⌘K is the command palette now; Ctrl-L clears natively in the
                // shell, so Clear is a menu-only convenience.
                Button("Clear") { Self.send(#selector(GhosttyMacSurface.terminalClearScreen(_:))) }
                Divider()
                Button("Bigger Text") { Self.send(#selector(GhosttyMacSurface.terminalIncreaseFontSize(_:))) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Smaller Text") { Self.send(#selector(GhosttyMacSurface.terminalDecreaseFontSize(_:))) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { Self.send(#selector(GhosttyMacSurface.terminalResetFontSize(_:))) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("Scroll Up") { Self.send(#selector(GhosttyMacSurface.terminalScrollPageUp(_:))) }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                Button("Scroll Down") { Self.send(#selector(GhosttyMacSurface.terminalScrollPageDown(_:))) }
                    .keyboardShortcut(.downArrow, modifiers: [.command])
                Button("Scroll to Top") { Self.send(#selector(GhosttyMacSurface.terminalScrollToTop(_:))) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Scroll to Bottom") { Self.send(#selector(GhosttyMacSurface.terminalScrollToBottom(_:))) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            }
        }

        Settings { MacSettingsView() }
    }

    /// Dispatch a terminal action to whichever GhosttyMacSurface is the first
    /// responder (the focused terminal — plain, session, or future split).
    private static func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}

/// App-level state shared between the window and the menu commands: the
/// terminal workspace's tabs + which sidebar section is showing.
@Observable
@MainActor
final class MacTerminalModel {
    /// Open terminal tabs (each owns its surface). The detail pane shows the
    /// selected one when `section == .terminal`.
    var tabs: [WorkspaceTab] = []
    var selectedTabID: UUID?
    /// Which sidebar section is selected. On the model (not local @State) so
    /// opening a Project / connecting can flip back to the terminal.
    /// Which sidebar section is selected. Switching sections clears any active
    /// search (and ends a terminal scrollback search so highlights don't linger).
    var section: MacSection = .terminal {
        didSet {
            guard section != oldValue else { return }
            if oldValue == .terminal { focusedSurface?.searchEnd() }
            showingSearch = false
            searchQuery = ""
        }
    }
    var showingAddHost = false
    var showingAddProject = false
    var showingCommandPalette = false
    var showingPairing = false
    /// Context-aware find (⌘F): searches the *current* section — terminal
    /// scrollback, or filters the Files/Machines/Projects/Agents list.
    var showingSearch = false
    var searchQuery = ""

    /// The surface that find/search and focused-pane actions target.
    var focusedSurface: GhosttyMacSurface? { selectedTab?.focusedPane?.surface }

    /// ⌘F — context-aware. In the terminal it opens scrollback search; in a
    /// list section it reveals that section's filter field.
    func showFind() {
        if section == .terminal { ensureTerminalTab() }
        showingSearch = true
    }
    func findNext() { focusedSurface?.searchNavigate(next: true) }
    func findPrevious() { focusedSurface?.searchNavigate(next: false) }

    var selectedTab: WorkspaceTab? { tabs.first { $0.id == selectedTabID } }

    private let openTabsKey = "shio.mac.openTabs"
    private var didRestore = false
    private var restoring = false

    /// On first show, restore the previous session's tabs; otherwise (or if
    /// none) open a plain shell so the terminal is never empty.
    /// Jump to a sidebar section (⌘⇧ T/P/M/A/F). Switching to Terminal also
    /// makes sure a tab exists so it's never an empty void.
    func show(_ target: MacSection) {
        section = target
        if target == .terminal { ensureTerminalTab() }
    }

    func ensureTerminalTab() {
        if !didRestore {
            didRestore = true
            restoreTabs()
        }
        if tabs.isEmpty { newLocalTab() }
    }

    @discardableResult
    private func addTab(_ content: TerminalPane.Content, title: String) -> WorkspaceTab {
        let tab = WorkspaceTab(pane: TerminalPane(content: content), title: title)
        tabs.append(tab)
        selectedTabID = tab.id
        section = .terminal     // surface the new tab
        persistTabs()
        return tab
    }

    // MARK: Tab persistence / restoration (relaunch)

    private func persistTabs() {
        guard !restoring else { return }
        let descriptors = tabs.compactMap { $0.descriptor }
        UserDefaults.standard.set(try? JSONEncoder().encode(descriptors), forKey: openTabsKey)
    }

    private func restoreTabs() {
        // One-time reset: older builds could persist a "This Mac" project as an
        // SSH-to-itself tab (it restored as a blank, dead terminal). Clear the
        // saved tabs once so that ghost tab doesn't come back; fresh tabs persist
        // correctly from here on.
        let resetKey = "shio.mac.tabsResetV1"
        if !UserDefaults.standard.bool(forKey: resetKey) {
            UserDefaults.standard.set(true, forKey: resetKey)
            UserDefaults.standard.removeObject(forKey: openTabsKey)
            return
        }
        guard let data = UserDefaults.standard.data(forKey: openTabsKey),
              let descriptors = try? JSONDecoder().decode([TabDescriptor].self, from: data),
              !descriptors.isEmpty else { return }
        restoring = true
        for d in descriptors { reopen(d) }
        restoring = false
        persistTabs()
    }

    private func reopen(_ d: TabDescriptor) {
        switch d.kind {
        case .shell:
            addTab(.shell(GhosttyMacSurface(backend: .local)), title: d.title)
        case .localProject:
            guard let path = d.path else { return }
            addTab(.project(MacLocalProjectSession(name: d.title, path: path, cloneURL: d.cloneURL)), title: d.title)
        case .ssh:
            guard let host = d.host, let port = d.port, let user = d.user else { return }
            let session = MacSSHSession(host: host, port: port, username: user, password: nil, resumeCommand: d.resume)
            openSSH(session, title: d.title)
        }
    }

    // MARK: Splits (act on the selected tab's focused pane)

    func splitFocused(_ direction: SplitDirection) {
        guard section == .terminal else { return }
        selectedTab?.split(direction)
    }

    func newLocalTab() {
        addTab(.shell(GhosttyMacSurface(backend: .local)), title: "Terminal")
    }

    /// Open a Project as a tab: local invisible-tmux (`.local` backend) for
    /// This-Mac projects; SSH (attach `shio-<project>`, clone-on-first-open)
    /// for projects that live on a machine. Used by the Projects list and the
    /// Add-Project sheet alike.
    func open(project: Project) {
        if let repo = project.activeRepo { open(repo: repo) }
        else { open(project: project, checkout: project.activeCheckout) }
    }

    /// Open a specific repo (the project-first path) on its active checkout. The
    /// tmux session is named per-repo (`shio-<repo>`), so different repos in one
    /// project are independent sessions.
    func open(repo: Repo) {
        let checkout = repo.activeCheckout
        let host = checkout?.host
        let path = checkout?.path ?? ""
        repo.lastOpenedAt = .now
        checkout?.lastOpenedAt = .now
        repo.project?.lastOpenedAt = .now
        // Ground the exact checkout being opened — the store-wide "active"
        // one can belong to another repo or the previously used machine.
        if let project = repo.project {
            SkillMaterializer.shared.materialize(project: project, checkout: checkout,
                                                 isLocalHost: MacSelfHost.isThisMac)
        }
        let tmuxName = "shio-\(TmuxResume.scrubName(repo.name))"
        if let host, !MacSelfHost.isThisMac(host) {
            let resume = TmuxResume.resumeCommand(named: tmuxName, startDir: path, cloneURL: repo.cloneURL)
            let session = MacSSHSession(host: host.hostname, port: host.port,
                                        username: host.username, password: nil, resumeCommand: resume)
            openSSH(session, title: repo.name)
        } else {
            addTab(.project(MacLocalProjectSession(name: repo.name, path: path, cloneURL: repo.cloneURL)),
                   title: repo.name)
        }
    }

    /// Open a project on a specific machine checkout (the machine switcher's path).
    /// nil checkout falls back to the legacy fields during the migration window.
    func open(project: Project, checkout: ProjectCheckout?) {
        let host = checkout?.host ?? project.host
        let path = checkout?.path ?? project.path
        checkout?.lastOpenedAt = .now
        SkillMaterializer.shared.materialize(project: project, checkout: checkout,
                                             isLocalHost: MacSelfHost.isThisMac)
        // This Mac (its own host) or a legacy host-less project → local
        // invisible-tmux. A project on another machine → SSH.
        if let host, !MacSelfHost.isThisMac(host) {
            let resume = TmuxResume.resumeCommand(
                named: "shio-\(TmuxResume.scrubName(project.name))",
                startDir: path,
                cloneURL: project.effectiveCloneURL
            )
            let session = MacSSHSession(host: host.hostname, port: host.port,
                                        username: host.username, password: nil,
                                        resumeCommand: resume)
            openSSH(session, title: project.name)
        } else {
            addTab(.project(MacLocalProjectSession(name: project.name, path: path, cloneURL: project.effectiveCloneURL)),
                   title: project.name)
        }
    }

    /// Open an SSH session as a tab and connect it.
    func openSSH(_ session: MacSSHSession, title: String) {
        addTab(.ssh(session), title: title)
        Task { await session.connect() }
    }

    /// Connect to a saved machine (key auth, or a one-shot password for the
    /// first connect before the machine has authorized the key).
    func connect(to host: Host, password: String? = nil) {
        let session = MacSSHSession(host: host.hostname, port: host.port,
                                    username: host.username, password: password)
        openSSH(session, title: host.name)
    }

    func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: idx)
        Task { await tab.stopAll() }
        if selectedTabID == id {
            selectedTabID = (idx < tabs.count ? tabs[idx] : tabs.last)?.id
        }
        persistTabs()
    }

    /// ⌘W. Closes the focused **pane**; if that was the tab's only pane, closes
    /// the tab. Only acts when the terminal is showing, so it never invisibly
    /// kills a background tab/pane while you're browsing Projects/Files. Closing
    /// the last tab lands on the empty-terminal state (the window stays — the
    /// red traffic light closes the window).
    func closeSelectedTab() {
        guard section == .terminal, let tab = selectedTab else { return }
        if tab.isSinglePane {
            closeTab(tab.id)
        } else {
            tab.closeFocusedPane()
        }
    }

    func selectTab(at index: Int) {
        if tabs.indices.contains(index) { selectedTabID = tabs[index].id }
    }

    /// Cycle the selection by `delta` (wraps around).
    func selectAdjacentTab(_ delta: Int) {
        guard !tabs.isEmpty,
              let id = selectedTabID,
              let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let n = tabs.count
        selectedTabID = tabs[((i + delta) % n + n) % n].id
    }
}

