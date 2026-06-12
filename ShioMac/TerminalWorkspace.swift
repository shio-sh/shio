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
        VStack(spacing: 0) {
            if model.tabs.count > 1 {
                TabStrip(model: model)
                Divider()
            }
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
        .onAppear { model.ensureTerminalTab() }
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

// MARK: - Tab strip

private struct TabStrip: View {
    @Bindable var model: MacTerminalModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.tabs) { tab in
                    TabChip(
                        tab: tab,
                        isSelected: tab.id == model.selectedTabID,
                        select: { model.selectedTabID = tab.id },
                        close: { model.closeTab(tab.id) }
                    )
                    Divider().frame(height: 16)
                }
                Button { model.newLocalTab() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New tab (⌘T)")
                Spacer(minLength: 0)
            }
        }
        .frame(height: 30)
        // Solid, opaque chrome — NOT `.bar`. The `.bar` material triggers
        // macOS's unified titlebar, which extends the strip's tint up through
        // the window title to the very top of the window (the "color goes to the
        // top" glitch). An explicit window-background keeps the strip contained.
        .background(ShioTheme.background)
    }
}

private struct TabChip: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            // Reserve the close-button slot so the title never shifts, and reveal
            // the × on hover only — tying it to selection makes it hop from tab to
            // tab as you click around, which reads as a glitch.
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 12)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .frame(maxWidth: 180)
        // A contained, inset pill — clearly within the strip, so the selected
        // state can never read as a full-height column.
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.10)
                      : (hovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}
