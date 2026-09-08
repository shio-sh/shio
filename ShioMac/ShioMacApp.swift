import SwiftUI
import SwiftData
import Sparkle

/// Shio for Mac — a native AppKit/SwiftUI app hosting libghostty (NOT Mac
/// Catalyst). Shares the platform-agnostic core (SSH, profiles, keys,
/// design tokens) with the iOS app via target membership in project.yml.
///
/// Current state: a working native local terminal, plus a minimal SSH session
/// path that attaches the same tmux session the phone uses (continuity). The
/// full Projects/Hosts/Files org + iCloud sync + the proper chrome land
/// in the next milestones.
@main
struct ShioMacApp: App {
    @State private var model = MacTerminalModel()
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    // Sparkle: in-app auto-update. `startingUpdater: true` begins the background
    // update schedule at launch; the "Check for Updates…" menu item drives a
    // manual check. Feed + key are in Info.plist (SUFeedURL / SUPublicEDKey).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            MacShell(model: model)
                .modelContainer(ShioModelContainer.shared)
        }
        .defaultSize(width: 1000, height: 640)
        // The rail runs to the very top of the window — traffic lights live
        // inside it. No titlebar band exists, so no second chrome color can
        // (and no toolbar may ever exist — it eats the headers' clicks).
        .windowStyle(.hiddenTitleBar)
        .commands {
            // "Check for Updates…" in the app menu, right under About Shio
            // (the standard spot). Sparkle also checks automatically in the
            // background — this is the manual trigger.
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            // Copy/Paste come from SwiftUI's default Edit menu — those route
            // copy:/paste: to the focused GhosttyMacSurface via the responder
            // chain, so no custom Edit items are needed.
            CommandGroup(after: .newItem) {
                // The escape hatch: an EXTRA indexed shell on the current
                // place's machine ("This Mac · 2") — its rail row lives
                // exactly as long as it does.
                Button("New Shell Here") { model.newShellHere() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Command Palette…") { model.showingCommandPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Refresh") {
                    Task { await SyncRefresh.run(ShioModelContainer.shared.mainContext) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Machines") {
                Button("Add Machine…") { model.showingAddHost = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            // A first run you can only ever see once is a first run nobody can
            // check. Help ▸ Welcome is where Mac apps put this.
            CommandGroup(replacing: .help) {
                Button("Show Welcome") {
                    UserDefaults.standard.removeObject(forKey: MacOnboarding.completedKey)
                    NotificationCenter.default.post(name: .shioShowWelcome, object: nil)
                }
            }
            // Jump straight to a canvas. Mnemonic ⌘⇧+letter — plain ⌘+letter
            // is taken by Tab/Find/Minimize/SelectAll.
            CommandMenu("Go") {
                Button(model.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") {
                    withAnimation(.easeOut(duration: 0.15)) { model.sidebarCollapsed.toggle() }
                }
                .keyboardShortcut("\\", modifiers: .command)
                Button(model.inspectorOpen ? "Hide Inspector" : "Show Inspector") {
                    model.inspectorOpen.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
                Divider()
                Button("Dashboard") { model.canvas = .dashboard }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Terminal") { model.showTerminal() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Machines") { model.canvas = .machines }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Files") { model.canvas = .files }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Places") {
                // ⌘W: furniture closes (a split pane); a place is LEFT — the
                // renderer frees, tmux keeps it alive, the rail row remains.
                Button(model.selectedTab?.isSinglePane == false ? "Close Pane" : "Leave Place") {
                    model.leavePlace()
                }
                .keyboardShortcut("w", modifiers: .command)
                Divider()
                Button("Next Place") { model.selectAdjacentPlace(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Place") { model.selectAdjacentPlace(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                // ⌘1–9 mirror the rail top-to-bottom (repos → shells).
                ForEach(1...9, id: \.self) { n in
                    Button("Place \(n)") { model.selectPlace(at: n - 1) }
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
/// selected project (team), the open tabs (repo terminals + shells), and which
/// canvas the center shows.
@Observable
@MainActor
final class MacTerminalModel {
    /// Open terminal tabs (each owns its surface). The terminal canvas
    /// shows the selected one; the rail's SHELLS/REPOS rows select them.
    var tabs: [WorkspaceTab] = []
    var selectedTabID: UUID? {
        didSet {
            guard oldValue != selectedTabID else { return }
            // Stamp both sides of the switch: the deselected tab's idle
            // clock starts now; the selected one resets.
            tabs.first { $0.id == oldValue }?.lastActiveAt = .now
            tabs.first { $0.id == selectedTabID }?.lastActiveAt = .now
        }
    }

    /// THE rail's collapse state (persisted). Toggled by the fixed ◧ beside
    /// the traffic lights, or ⌘\.
    var sidebarCollapsed: Bool = UserDefaults.standard.bool(forKey: "shio.mac.sidebarCollapsed") {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: "shio.mac.sidebarCollapsed") }
    }

    static let selectedProjectKey = "shio.mac.project"
    /// The team on deck — the rail, dashboard, and switcher all read it.
    /// MacRail keeps it resolved (persisted by name across launches).
    var selectedProject: Project? {
        didSet { UserDefaults.standard.set(selectedProject?.name, forKey: Self.selectedProjectKey) }
    }
    /// The switcher's ▾ dropdown — overlays the rail, never pushes it.
    var showingProjectMenu = false

    /// The GLANCE inspector — OPEN by default (closing it is focus mode).
    /// ⌘I and every header's ▤ toggle it, lit state synced.
    var inspectorOpen: Bool = (UserDefaults.standard.object(forKey: "shio.mac.inspectorOpen") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(inspectorOpen, forKey: "shio.mac.inspectorOpen") }
    }

    /// Which canvas fills the center. Switching clears any active search (and
    /// ends a terminal scrollback search so highlights don't linger).
    var canvas: MacCanvas = .dashboard {
        didSet {
            guard canvas != oldValue else { return }
            if oldValue == .terminal { focusedSurface?.searchEnd() }
            showingSearch = false
            searchQuery = ""
        }
    }

    /// Pick a team: land on its dashboard (overview first — his call).
    func select(project: Project) {
        showingProjectMenu = false
        selectedProject = project
        project.lastOpenedAt = .now
        canvas = .dashboard
    }

    var showingAddHost = false
    var showingAddProject = false
    /// Set to a project to open the add-repo sheet for it (rail + dashboard).
    var addRepoToProject: Project?
    var showingCommandPalette = false
    var showingPairing = false
    /// Context-aware find (⌘F): searches the *current* section — terminal
    /// scrollback, or filters the Files/Machines/Projects list.
    var showingSearch = false
    var searchQuery = ""

    /// The surface that find/search and focused-pane actions target.
    var focusedSurface: GhosttyMacSurface? { selectedTab?.focusedPane?.surface }

    /// ⌘F — context-aware. In a terminal it opens scrollback search; in a
    /// list canvas it reveals that canvas's filter field.
    func showFind() {
        if canvas == .terminal { ensureTerminalTab() }
        showingSearch = true
    }
    func findNext() { focusedSurface?.searchNavigate(next: true) }
    func findPrevious() { focusedSurface?.searchNavigate(next: false) }

    var selectedTab: WorkspaceTab? { tabs.first { $0.id == selectedTabID } }

    private let openTabsKey = "shio.mac.openTabs"
    private var didRestore = false
    private var restoring = false

    /// Jump to the terminal canvas (⌘⇧T), making sure a tab exists so it's
    /// never an empty void.
    func showTerminal() {
        ensureTerminalTab()
        canvas = .terminal
    }

    /// Bring an existing tab on screen (the rail's rows).
    func focus(_ tab: WorkspaceTab) {
        selectedTabID = tab.id
        canvas = .terminal
    }

    /// Restore the previous run's tabs once — called at launch so the rail's
    /// SHELLS/REPOS rows light up without visiting the terminal first.
    func ensureRestored() {
        if !didRestore {
            didRestore = true
            restoreTabs()
        }
    }

    func ensureTerminalTab() {
        ensureRestored()
        if tabs.isEmpty { newLocalTab() }
    }

    @discardableResult
    private func addTab(_ content: TerminalPane.Content, title: String, isShell: Bool = false) -> WorkspaceTab {
        let tab = WorkspaceTab(pane: TerminalPane(content: content), title: title, isShell: isShell)
        tabs.append(tab)
        selectedTabID = tab.id
        if !restoring { canvas = .terminal }   // surface the new tab
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
            addTab(.shell(GhosttyMacSurface(backend: .local)), title: d.title, isShell: true)
        case .localProject:
            guard let path = d.path else { return }
            addTab(.project(MacLocalProjectSession(name: d.title, path: path, cloneURL: d.cloneURL)), title: d.title)
        case .ssh:
            guard let host = d.host, let port = d.port, let user = d.user else { return }
            let session = MacSSHSession(host: host, port: port, username: user, password: nil, resumeCommand: d.resume)
            openSSH(session, title: d.title, isShell: d.shell ?? false)
        }
    }

    // MARK: Splits (act on the selected tab's focused pane)

    func splitFocused(_ direction: SplitDirection) {
        guard canvas == .terminal else { return }
        selectedTab?.split(direction)
    }

    func newLocalTab() {
        addTab(.shell(GhosttyMacSurface(backend: .local)), title: "This Mac", isShell: true)
    }

    /// This Mac's ONE shell — focus it if alive, else open it.
    func openLocalShell() {
        if let existing = tabs.first(where: { $0.isShellTab && $0.title == "This Mac" }) {
            focus(existing)
        } else {
            newLocalTab()
        }
    }

    /// The escape hatch (⌘T): an ADDITIONAL indexed shell on the current
    /// place's machine — "This Mac · 2". Its rail row exists while the shell
    /// does, then folds away. Anywhere that isn't a remote place means this
    /// Mac; with no shell yet on the machine, this opens its first.
    func newShellHere() {
        var base = "This Mac"
        var remote: MacSSHSession? = nil
        if canvas == .terminal, let pane = selectedTab?.root.firstLeafPane,
           case .ssh(let s) = pane.content {
            base = shellTitle(matching: s)
            remote = s
        }
        let next = nextShellIndex(base: base)
        let title = next == 1 ? base : "\(base) · \(next)"
        if let remote {
            // Reuse the cross-device tmux naming (shio-<host>, shio-<host>-1,
            // …) so the phone resumes these too.
            let session = MacSSHSession(host: remote.hostName, port: remote.port,
                                        username: remote.username, password: nil,
                                        resumeCommand: TmuxResume.resumeCommand(for: remote.hostName,
                                                                                index: next - 1))
            openSSH(session, title: title, isShell: true)
        } else {
            addTab(.shell(GhosttyMacSurface(backend: .local)), title: title, isShell: true)
        }
    }

    /// A machine's shell title on the rail ("This Mac" for the self host).
    static func shellTitle(for host: Host) -> String {
        MacSelfHost.isThisMac(host) ? "This Mac" : host.name
    }

    /// The saved machine's display name for an SSH place; the raw hostname
    /// stands in when the machine isn't saved.
    private func shellTitle(matching session: MacSSHSession) -> String {
        let host = Self.fetchHosts().first {
            $0.hostname == session.hostName && $0.username == session.username && $0.port == session.port
        }
        return host.map(Self.shellTitle(for:)) ?? session.hostName
    }

    /// 1 for the machine's first shell (the base, unsuffixed), else max + 1.
    private func nextShellIndex(base: String) -> Int {
        let indices = tabs.filter(\.isShellTab).compactMap { tab -> Int? in
            if tab.title == base { return 1 }
            guard tab.title.hasPrefix("\(base) · "),
                  let n = Int(tab.title.dropFirst(base.count + 3)) else { return nil }
            return n
        }
        return (indices.max() ?? 0) + 1
    }

    private static func fetchHosts() -> [Host] {
        let d = FetchDescriptor<Host>(sortBy: [SortDescriptor(\.name)])
        return ((try? ShioModelContainer.shared.mainContext.fetch(d)) ?? []).dedupedByIdentity
    }

    /// A repo's terminal is STANDING — opening it again refocuses the
    /// existing tab instead of spawning a second one.
    private func focusTab(named name: String) -> Bool {
        guard let existing = tabs.first(where: { !$0.isShellTab && $0.title == name }) else { return false }
        focus(existing)
        return true
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
        if let project = repo.project { selectedProject = project }
        repo.lastOpenedAt = .now
        repo.project?.lastOpenedAt = .now
        if focusTab(named: repo.name) { return }
        let checkout = repo.activeCheckout
        let host = checkout?.host
        let path = checkout?.path ?? ""
        checkout?.lastOpenedAt = .now
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
        selectedProject = project
        if focusTab(named: project.name) { return }
        let host = checkout?.host ?? project.host
        let path = checkout?.path ?? project.path
        checkout?.lastOpenedAt = .now
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

    /// Open an SSH terminal as a tab and connect it. `isShell` marks a loose
    /// per-machine shell (the rail's SHELLS group) vs a repo terminal.
    func openSSH(_ session: MacSSHSession, title: String, isShell: Bool = false) {
        addTab(.ssh(session), title: title, isShell: isShell)
        Task { await session.connect() }
    }

    /// The machine's ONE shell — focus it if alive, else connect (key auth,
    /// or a one-shot password for the first connect before the machine has
    /// authorized the key). Connecting again never spawns a second shell;
    /// that's what New Shell Here is for.
    func connect(to host: Host, password: String? = nil) {
        let title = Self.shellTitle(for: host)
        if let existing = tabs.first(where: { $0.isShellTab && $0.title == title }) {
            // Fresh credentials mean a fresh connection — replace, don't stack.
            guard password != nil else { focus(existing); return }
            closeTab(existing.id)
        }
        if MacSelfHost.isThisMac(host) {
            newLocalTab()   // never SSH into ourselves
            return
        }
        let session = MacSSHSession(host: host.hostname, port: host.port,
                                    username: host.username, password: password)
        openSSH(session, title: title, isShell: true)
    }

    // MARK: Hibernation (the RAM lever tmux makes safe)

    /// How long a background terminal keeps its live surface. The surface
    /// (scrollback buffer + Metal textures) is where the app's memory goes;
    /// tmux holds the real session, so releasing it is lossless.
    static let hibernateAfter: TimeInterval = 15 * 60
    private var hibernateTimer: Timer?

    /// Sweep idle background terminals once a minute: close their tabs
    /// (freeing the renderer), keep the standing session in tmux —
    /// clicking the repo row reattaches with scrollback intact.
    func startHibernator() {
        guard hibernateTimer == nil else { return }
        hibernateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweepIdleTabs() }
        }
    }

    private func sweepIdleTabs() {
        let cutoff = Date.now.addingTimeInterval(-Self.hibernateAfter)
        for tab in tabs where tab.id != selectedTabID
            && tab.isHibernatable
            && tab.lastActiveAt < cutoff {
            closeTab(tab.id)
        }
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

    /// ⌘W. On a split it closes the focused **pane** — furniture. On a
    /// single-pane place it LEAVES: the renderer frees (the closeTab
    /// machinery; tmux keeps the place alive) and you land back on the
    /// dashboard. The rail row remains — places don't close; only an indexed
    /// escape-hatch shell's row folds away with it. Only acts while a
    /// terminal is showing, so it never invisibly kills background work.
    func leavePlace() {
        guard canvas == .terminal, let tab = selectedTab else { return }
        if tab.isSinglePane {
            closeTab(tab.id)
            canvas = .dashboard
        } else {
            tab.closeFocusedPane()
        }
    }

    // MARK: The rail map (places)

    /// Go to the n-th rail row (⌘1–9) — the rail order IS the shortcut order.
    func selectPlace(at index: Int) {
        let places = railMap().places
        guard places.indices.contains(index) else { return }
        go(to: places[index])
    }

    /// Walk the map (⇧⌘] / ⇧⌘[) — cycles the unique places in rail order.
    func selectAdjacentPlace(_ delta: Int) {
        let cycle = railMap().cycle
        guard !cycle.isEmpty else { return }
        let next: Int
        if let i = cycle.firstIndex(where: isCurrent) {
            let n = cycle.count
            next = ((i + delta) % n + n) % n
        } else {
            next = delta > 0 ? 0 : cycle.count - 1
        }
        go(to: cycle[next])
    }

    func go(to place: RailMap.Place) {
        switch place {
        case .repo(let repo): open(repo: repo)
        case .machine(let host): connect(to: host)
        case .shell(let tab): focus(tab)
        }
    }

    /// Whether a place is the one on screen.
    private func isCurrent(_ place: RailMap.Place) -> Bool {
        guard canvas == .terminal, let tab = selectedTab else { return false }
        switch place {
        case .repo(let repo): return !tab.isShellTab && tab.title == repo.name
        case .machine(let host): return tab.isShellTab && tab.title == Self.shellTitle(for: host)
        case .shell(let t): return t.id == tab.id
        }
    }

    /// ONE builder feeds both what the rail draws and what ⌘1–9 / ⇧⌘]
    /// target, so the keys can never drift from the pixels.
    func railMap() -> RailMap {
        var map = RailMap()
        map.repos = selectedProject.map { ProjectRows.rows(for: $0) } ?? []

        // SHELLS is the permanent machine map (This Mac leads), each row the
        // machine's one shell; indexed escape-hatch shells ride under their
        // machine while they exist.
        var claimed = Set<UUID>()
        let shellTabs = tabs.filter(\.isShellTab)
        for host in Self.fetchHosts().sorted(by: { a, _ in MacSelfHost.isThisMac(a) }) {
            map.shells.append(.machine(host))
            let base = Self.shellTitle(for: host)
            claimed.formUnion(shellTabs.filter { $0.title == base }.map(\.id))
            for tab in shellTabs where tab.title.hasPrefix("\(base) · ") {
                map.shells.append(.tab(tab))
                claimed.insert(tab.id)
            }
        }
        // A shell whose machine record is gone still gets a row while it
        // lives — nothing on screen may silently vanish.
        for tab in shellTabs where !claimed.contains(tab.id) {
            map.shells.append(.tab(tab))
        }

        let shellPlaces = map.shells.map(\.place)
        map.places = map.repos.map { .repo($0.repo) } + shellPlaces
        map.cycle = map.repos.map { .repo($0.repo) } + shellPlaces
        return map
    }
}

/// The rail's display model: the two groups in display order (repos →
/// shells) plus the flattened `places` the shortcuts index into.
struct RailMap {
    enum Place {
        case repo(Repo)
        case machine(Host)
        case shell(WorkspaceTab)
    }

    /// A row in the SHELLS group: a machine (permanent — its one shell), or
    /// an indexed escape-hatch shell (alive only while it exists).
    enum ShellRow: Identifiable {
        case machine(Host)
        case tab(WorkspaceTab)
        var id: AnyHashable {
            switch self {
            case .machine(let h): return h.persistentModelID
            case .tab(let t): return t.id
            }
        }
        var place: Place {
            switch self {
            case .machine(let h): return .machine(h)
            case .tab(let t): return .shell(t)
            }
        }
    }

    var repos: [RepoRowVM] = []
    var shells: [ShellRow] = []
    /// Every visible row top-to-bottom — the ⌘1–9 targets.
    var places: [Place] = []
    /// Mirror-free places for next/previous cycling.
    var cycle: [Place] = []
}

