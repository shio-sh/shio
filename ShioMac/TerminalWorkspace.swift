import SwiftUI

/// One tab in the Mac terminal workspace. A tab owns a **tree of panes** (the
/// split layout) plus which pane is focused. `isShellTab` marks a loose
/// per-machine shell (the rail's SHELLS group); everything else is a repo's
/// standing conversation.
@MainActor
@Observable
final class WorkspaceTab: Identifiable {
    let id = UUID()
    var title: String
    let icon: String
    let isShellTab: Bool
    var root: SplitNode
    var focusedPaneID: UUID

    init(pane: TerminalPane, title: String, isShell: Bool = false) {
        self.title = title
        self.icon = pane.icon
        self.isShellTab = isShell
        self.root = SplitNode(.leaf(pane))
        self.focusedPaneID = pane.id
    }

    var isSinglePane: Bool { if case .leaf = root.kind { return true }; return false }
    var focusedPane: TerminalPane? { root.node(withPane: focusedPaneID)?.leafPane }

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
        guard let (parentBranch, isFirst) = root.parent(ofPane: focusedPaneID),
              case .branch(_, let a, let b) = parentBranch.kind else { return false }
        let closed = isFirst ? a.leafPane : b.leafPane
        let sibling = isFirst ? b : a
        parentBranch.kind = sibling.kind
        parentBranch.ratio = sibling.ratio
        if let closed { Task { await closed.stop() } }
        focusedPaneID = parentBranch.firstLeafPane?.id ?? focusedPaneID
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
    /// Loose machine shell vs repo conversation (nil in pre-rail data).
    var shell: Bool? = nil
}

/// The conversation canvas: the selected tab's terminal under its 48pt header
/// (presence glyph + name + quiet "agent · tmux · machine" metadata). The rail
/// owns tab switching; splits stay ⌘D / ⇧⌘D inside the canvas.
struct TerminalWorkspaceView: View {
    @Bindable var model: MacTerminalModel

    var body: some View {
        VStack(spacing: 0) {
            if let tab = model.selectedTab {
                conversationHead(tab)
            }
            workspace
        }
        .onAppear { model.ensureTerminalTab() }
    }

    private func conversationHead(_ tab: WorkspaceTab) -> some View {
        MacCanvasHeader(title: tab.title, sub: sub(for: tab)) {
            presenceGlyph(tab)
        } trailing: {
            MacHeaderIconButton(systemImage: "rectangle.split.2x1", help: "Split right (⌘D)") {
                model.splitFocused(.horizontal)
            }
            MacHeaderIconButton(systemImage: "sidebar.trailing", help: "Inspector (⌘I)",
                                on: model.inspectorOpen) {
                model.inspectorOpen.toggle()
            }
        }
    }

    /// ⚑ needs-you / ⠋ working / ⎇ quiet repo / % shell — the agent's
    /// presence on this conversation.
    @ViewBuilder private func presenceGlyph(_ tab: WorkspaceTab) -> some View {
        if tab.isShellTab {
            Text("%").font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
        } else {
            switch MacProjectAgentMonitor.shared.snapshot(forProjectNamed: tab.title)?.activity {
            case .waiting:
                Text("⚑").font(.system(size: 12))
                    .foregroundStyle(ShioTheme.warning)
                    .shioNeedsPulse()
            case .running:
                ShioBrailleSpinner(status: .info, size: 12)
            default:
                Text("⎇").font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
    }

    /// Quiet terminal-ish metadata: "Claude · tmux · this mac".
    private func sub(for tab: WorkspaceTab) -> String {
        let agent = tab.isShellTab ? nil
            : MacProjectAgentMonitor.shared.snapshot(forProjectNamed: tab.title)?.agentName
        let place: String?
        switch tab.root.firstLeafPane?.content {
        case .shell:          place = "zsh · this mac"
        case .project:        place = "tmux · this mac"
        case .ssh(let s):     place = "tmux · \(s.hostName)"
        case .none:           place = nil
        }
        return [agent, place].compactMap(\.self).joined(separator: " · ")
    }

    private var workspace: some View {
        Group {
            // The selected tab's split tree. Surfaces survive tab switches
            // because the tabs (not the views) own them.
            if let tab = model.selectedTab {
                SplitContainer(tab: tab, node: tab.root).id(tab.id)
            } else {
                // Closing the last tab lands here — an intentional empty state,
                // never a blank pane (which read as "the app closed").
                EmptyTerminalState { model.newLocalTab() }
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.showingSearch {
                TerminalSearchBar(model: model).padding(12)
            }
        }
        .overlay(alignment: .bottom) {
            // The agent's question is in the scrollback right above — this is
            // the one-keystroke answer. Local tmux only; a remote agent is
            // answered in its terminal directly.
            if let tab = model.selectedTab, !tab.isShellTab,
               let session = MacProjectAgentMonitor.shared.waitingSessionName(forProjectNamed: tab.title) {
                MacNeedBar(
                    agentName: MacProjectAgentMonitor.shared.byTmux[session]?.agentName ?? "Your agent",
                    approve: { MacProjectAgentMonitor.shared.send(key: "y", toSession: session) },
                    deny: { MacProjectAgentMonitor.shared.send(key: "n", toSession: session) }
                )
                .padding(14)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            }
        }
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
