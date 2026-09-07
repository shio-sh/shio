import SwiftUI

/// One tab in the Mac terminal workspace. A tab owns a **tree of panes** (the
/// split layout) plus which pane is focused. `isShellTab` marks a loose
/// per-machine shell (the rail's SHELLS group); everything else is a repo's
/// standing terminal.
@MainActor
@Observable
final class WorkspaceTab: Identifiable {
    let id = UUID()
    var title: String
    let icon: String
    let isShellTab: Bool
    var root: SplitNode
    var focusedPaneID: UUID
    /// When this tab was last on screen — the hibernation clock.
    var lastActiveAt: Date = .now

    init(pane: TerminalPane, title: String, isShell: Bool = false) {
        self.title = title
        self.icon = pane.icon
        self.isShellTab = isShell
        self.root = SplitNode(.leaf(pane))
        self.focusedPaneID = pane.id
    }

    var isSinglePane: Bool { if case .leaf = root.kind { return true }; return false }
    var focusedPane: TerminalPane? { root.node(withPane: focusedPaneID)?.leafPane }

    /// Lossless to close: the real session lives in tmux, so dropping the
    /// local surface (scrollback buffer + Metal textures — the app's RAM)
    /// costs nothing; reopening from the rail reattaches. Plain shells have
    /// no tmux behind them and split layouts shouldn't silently collapse, so
    /// neither hibernates.
    var isHibernatable: Bool {
        guard !isShellTab, isSinglePane else { return false }
        switch root.firstLeafPane?.content {
        case .project, .ssh: return true
        default: return false
        }
    }

    /// Split the focused pane, putting a fresh shell beside/below it.
    func split(_ direction: SplitDirection) {
        guard let node = root.node(withPane: focusedPaneID),
              case .leaf(let pane) = node.kind else { return }
        let newPane = TerminalPane.newShell()
        node.kind = .branch(direction, SplitNode(.leaf(pane)), SplitNode(.leaf(newPane)))
        node.ratio = 0.5
        focusedPaneID = newPane.id
    }

    /// Close the focused pane, collapsing its parent into the sibling. Returns
    /// false if the tab is a single pane (the caller closes the whole tab).
    @discardableResult
    func closeFocusedPane() -> Bool {
        close(paneID: focusedPaneID)
    }

    /// Close a specific pane (the hover ✕ on a split), collapsing its parent
    /// into the sibling. Returns false for a single-pane tab.
    @discardableResult
    func close(paneID: UUID) -> Bool {
        guard let (parentBranch, isFirst) = root.parent(ofPane: paneID),
              case .branch(_, let a, let b) = parentBranch.kind else { return false }
        let closed = isFirst ? a.leafPane : b.leafPane
        let sibling = isFirst ? b : a
        parentBranch.kind = sibling.kind
        parentBranch.ratio = sibling.ratio
        if let closed { Task { await closed.stop() } }
        if focusedPaneID == paneID || root.node(withPane: focusedPaneID) == nil {
            focusedPaneID = parentBranch.firstLeafPane?.id ?? focusedPaneID
        }
        return true
    }

    func stopAll() async {
        for pane in root.allPanes { await pane.stop() }
    }

    /// A persistable summary of this tab (its primary pane) for relaunch
    /// restoration. Splits aren't restored in v1 — the first leaf stands in.
    var descriptor: TabDescriptor? {
        guard let pane = root.firstLeafPane else { return nil }
        switch pane.content {
        case .shell:
            return TabDescriptor(kind: .shell, title: title, shell: true)
        case .project(let p):
            return TabDescriptor(kind: .localProject, title: title, path: p.path, cloneURL: p.cloneURL)
        case .ssh(let s):
            return TabDescriptor(kind: .ssh, title: title, host: s.hostName, port: s.port,
                                 user: s.username, resume: s.resumeCommand, shell: isShellTab)
        }
    }
}

/// Codable summary of an open tab, persisted so the workspace restores on
/// relaunch. SSH tabs reconnect (tmux reattaches); local projects reopen.
struct TabDescriptor: Codable {
    enum Kind: String, Codable { case shell, localProject, ssh }
    var kind: Kind
    var title: String
    var path: String? = nil
    var cloneURL: String? = nil
    var host: String? = nil
    var port: Int? = nil
    var user: String? = nil
    var resume: String? = nil
    /// Loose machine shell vs repo terminal (nil in pre-rail data).
    var shell: Bool? = nil
}

/// The terminal canvas: the selected tab's terminal under its 48pt header
/// (idle glyph + name + quiet "tmux · machine" metadata). The rail owns tab
/// switching; splits stay ⌘D / ⇧⌘D inside the canvas.
struct TerminalWorkspaceView: View {
    @Bindable var model: MacTerminalModel

    var body: some View {
        VStack(spacing: 0) {
            if let tab = model.selectedTab {
                terminalHead(tab)
            }
            workspace
        }
        .onAppear { model.ensureTerminalTab() }
    }

    private func terminalHead(_ tab: WorkspaceTab) -> some View {
        MacCanvasHeader(title: tab.title, sub: sub(for: tab)) {
            // ⎇ quiet repo / % shell — a static idle mark for this terminal.
            Text(tab.isShellTab ? "%" : "⎇")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
        } trailing: {
            // The escape hatch's small in-place affordance — shell places only.
            if tab.isShellTab {
                MacHeaderIconButton(systemImage: "plus.square", help: "New shell here (⌘T)") {
                    model.newShellHere()
                }
            }
            MacHeaderIconButton(systemImage: "rectangle.split.2x1", help: "Split right (⌘D)") {
                model.splitFocused(.horizontal)
            }
            MacHeaderIconButton(systemImage: "sidebar.trailing", help: "Inspector (⌘I)",
                                on: model.inspectorOpen) {
                model.inspectorOpen.toggle()
            }
        }
    }

    /// Quiet terminal-ish metadata: "tmux · this mac" — carrying the
    /// connection state when it isn't the happy path.
    private func sub(for tab: WorkspaceTab) -> String {
        switch tab.root.firstLeafPane?.content {
        case .shell:          return "zsh · this mac"
        case .project:        return "tmux · this mac"
        case .ssh(let s):
            switch s.state {
            case .reconnecting: return "reconnecting… · \(s.hostName)"
            case .failed:       return "disconnected · \(s.hostName)"
            case .connecting:   return "connecting… · \(s.hostName)"
            default:            return "tmux · \(s.hostName)"
            }
        case .none:           return ""
        }
    }

    private var workspace: some View {
        Group {
            // The selected tab's split tree. Surfaces survive tab switches
            // because the tabs (not the views) own them.
            if let tab = model.selectedTab {
                SplitContainer(tab: tab, node: tab.root).id(tab.id)
            } else {
                // Leaving the last place lands here — an intentional empty
                // state, never a blank pane (which read as "the app closed").
                EmptyTerminalState { model.openLocalShell() }
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.showingSearch {
                TerminalSearchBar(model: model).padding(12)
            }
        }
        .overlay(alignment: .bottom) { bottomOverlay }
    }

    /// One bottom slot: connection state (a reconnecting chip, or a Reconnect
    /// affordance once the retry budget is spent).
    @ViewBuilder private var bottomOverlay: some View {
        if let session = focusedSSHSession {
            switch session.state {
            case .reconnecting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(ShioTheme.textSecondary)
                    Text("Reconnecting…")
                        .font(.system(size: 12))
                        .foregroundStyle(ShioTheme.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(ShioTheme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(ShioTheme.line2))
                .padding(.bottom, 14)
            case .failed:
                ShioButton("Reconnect", .primary, icon: "arrow.clockwise") {
                    Task { await session.connect() }
                }
                .padding(.bottom, 14)
            default:
                EmptyView()
            }
        }
    }

    /// The selected tab's focused SSH session, if that's what's focused.
    private var focusedSSHSession: MacSSHSession? {
        guard let pane = model.selectedTab?.focusedPane ?? model.selectedTab?.root.firstLeafPane,
              case .ssh(let s) = pane.content else { return nil }
        return s
    }
}

/// Find-in-scrollback bar (⌘F). Drives the focused surface's ghostty search as
/// you type — ghostty renders the match highlights itself. ⏎/⇧⏎ and the arrows
/// step matches; esc closes.
private struct TerminalSearchBar: View {
    @Bindable var model: MacTerminalModel
    @FocusState private var focused: Bool

    private var surface: GhosttyMacSurface? { model.focusedSurface }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Find", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 160)
                .focused($focused)
                .onChange(of: model.searchQuery) { _, q in surface?.searchSet(q) }
                .onKeyPress(.return) {
                    surface?.searchNavigate(next: !NSEvent.modifierFlags.contains(.shift))
                    return .handled
                }
                .onKeyPress(.escape) { close(); return .handled }
            Button { surface?.searchNavigate(next: false) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
            Button { surface?.searchNavigate(next: true) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
            Button { close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(ShioTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(ShioTheme.line2))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .onAppear {
            focused = true
            if !model.searchQuery.isEmpty { surface?.searchSet(model.searchQuery) }
        }
    }

    private func close() {
        surface?.searchEnd()
        model.showingSearch = false
        // Hand focus back to the terminal.
        if let surface { surface.window?.makeFirstResponder(surface) }
    }
}

/// Shown when no tab is open (e.g. you closed the last one). Clearly the
/// terminal area at rest, with a one-tap way back in.
private struct EmptyTerminalState: View {
    let newTab: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            ShioCompanion()
            ShioButton("New shell", .primary, icon: "plus") { newTab() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioTheme.background)
    }
}
