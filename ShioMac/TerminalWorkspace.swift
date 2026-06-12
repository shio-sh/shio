import SwiftUI

/// One tab in the Mac terminal workspace. A tab owns a **tree of panes** (the
/// split layout) plus which pane is focused. The strip shows `title`/`icon`
/// from the pane it was opened with.
@MainActor
@Observable
final class WorkspaceTab: Identifiable {
    let id = UUID()
    var title: String
    let icon: String
    var root: SplitNode
    var focusedPaneID: UUID

    init(pane: TerminalPane, title: String) {
        self.title = title
        self.icon = pane.icon
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
            return TabDescriptor(kind: .shell, title: title)
        case .project(let p):
            return TabDescriptor(kind: .localProject, title: title, path: p.path, cloneURL: p.cloneURL)
        case .ssh(let s):
            return TabDescriptor(kind: .ssh, title: title, host: s.hostName, port: s.port, user: s.username, resume: s.resumeCommand)
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
}

/// The tabbed terminal workspace that fills the detail pane: a tab strip on
/// top (only when there's more than one tab — a lone terminal stays clean),
/// the selected tab's surface below. Each tab owns an independent surface; the
/// PTY/SSH keeps running while a tab is in the background.
struct TerminalWorkspaceView: View {
    @Bindable var model: MacTerminalModel

    var body: some View {
        HStack(spacing: 0) {
            if !model.sidebarCollapsed {
                MacSidebarColumn(model: model, title: "tabs") {
                    if model.tabs.isEmpty {
                        Text("No open tabs.")
                            .font(.system(size: 12))
                            .foregroundStyle(ShioTheme.textTertiary)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    } else {
                        ForEach(model.tabs) { tab in tabRow(tab) }
                    }
                } actions: {
                    Button { model.newLocalTab() } label: {
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("New tab (⌘T)")
                }
                MacSidebarDivider()
            }
            workspace
        }
        .onAppear { model.ensureTerminalTab() }
    }

    // No tab strip: the rail owns tabs (his call, 2026-06-12). Splits stay
    // ⌘D / ⇧⌘D inside the canvas.
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
    }

    private func tabRow(_ tab: WorkspaceTab) -> some View {
        TabRailRow(model: model, tab: tab)
    }
}

/// One tab in the rail: select on click, ✕ reveals on hover (the strip is
/// gone — this row is the tab's only home).
private struct TabRailRow: View {
    @Bindable var model: MacTerminalModel
    let tab: WorkspaceTab
    @State private var hovering = false

    var body: some View {
        let isSel = model.selectedTabID == tab.id
        Button { model.selectedTabID = tab.id } label: {
            HStack(spacing: 9) {
                Text(isSel ? "%" : "·")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 12)
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textTertiary)
                Text(tab.title)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if hovering {
                    Button { model.closeTab(tab.id) } label: {
                        Text("✕")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Close tab (⌘W)")
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSel ? ShioTheme.accentBg : (hovering ? ShioTheme.hover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
            Button(action: newTab) {
                Label("New Tab", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


