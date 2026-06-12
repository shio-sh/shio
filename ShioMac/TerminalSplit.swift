import SwiftUI

/// A split orientation. `.horizontal` puts panes **side by side** (a vertical
/// divider, ⌘D "split right"); `.vertical` **stacks** them (a horizontal
/// divider, ⌘⇧D "split down").
enum SplitDirection {
    case horizontal, vertical
}

/// A single terminal pane — wraps the surface-bearing thing behind a uniform
/// surface, exactly like a tab used to. A tab now holds a *tree* of these.
@MainActor
@Observable
final class TerminalPane: Identifiable {
    let id = UUID()

    enum Content {
        case shell(GhosttyMacSurface)         // plain local login shell
        case project(MacLocalProjectSession)  // local invisible-tmux project
        case ssh(MacSSHSession)               // remote / host session
    }
    let content: Content

    init(content: Content) { self.content = content }

    /// A fresh plain-shell pane — what a new split opens.
    static func newShell() -> TerminalPane {
        TerminalPane(content: .shell(GhosttyMacSurface(backend: .local)))
    }

    var surface: GhosttyMacSurface {
        switch content {
        case .shell(let s):   return s
        case .project(let p): return p.surface
        case .ssh(let s):     return s.surface
        }
    }

    var icon: String {
        switch content {
        case .shell:   return "terminal"
        case .project: return "folder.fill"
        case .ssh:     return "desktopcomputer"
        }
    }

    func stop() async {
        switch content {
        case .shell:          break
        case .project(let p): await p.stop()
        case .ssh(let s):     await s.stop()
        }
        surface.shutdown()   // free the libghostty surface + release its +1 (else it leaks)
    }
}

/// A node in a tab's split tree: a leaf pane, or a branch splitting two
/// subtrees with a resize `ratio` (fraction given to the first child).
@MainActor
@Observable
final class SplitNode: Identifiable {
    let id = UUID()

    enum Kind {
        case leaf(TerminalPane)
        case branch(SplitDirection, SplitNode, SplitNode)
    }
    var kind: Kind
    var ratio: CGFloat = 0.5

    init(_ kind: Kind) { self.kind = kind }

    // MARK: Tree queries (all main-actor; the tree is small)

    var leafPane: TerminalPane? {
        if case .leaf(let p) = kind { return p }; return nil
    }
    var branch: (SplitDirection, SplitNode, SplitNode)? {
        if case .branch(let d, let a, let b) = kind { return (d, a, b) }; return nil
    }

    /// The node whose leaf holds `paneID`.
    func node(withPane paneID: UUID) -> SplitNode? {
        if leafPane?.id == paneID { return self }
        if let (_, a, b) = branch { return a.node(withPane: paneID) ?? b.node(withPane: paneID) }
        return nil
    }

    /// The branch directly parenting the leaf for `paneID`, and whether that
    /// leaf is its `first` child.
    func parent(ofPane paneID: UUID) -> (branch: SplitNode, isFirst: Bool)? {
        guard let (_, a, b) = branch else { return nil }
        if a.leafPane?.id == paneID { return (self, true) }
        if b.leafPane?.id == paneID { return (self, false) }
        return a.parent(ofPane: paneID) ?? b.parent(ofPane: paneID)
    }

    var firstLeafPane: TerminalPane? {
        if let p = leafPane { return p }
        if let (_, a, _) = branch { return a.firstLeafPane }
        return nil
    }

    var allPanes: [TerminalPane] {
        if let p = leafPane { return [p] }
        if let (_, a, b) = branch { return a.allPanes + b.allPanes }
        return []
    }
}

// MARK: - Recursive split view

/// Renders a tab's split tree: a leaf hosts its surface; a branch uses AppKit's
/// native split view (HSplitView side-by-side, VSplitView stacked) for the
/// divider, dragging, and min-size handling — robust and crash-free.
struct SplitContainer: View {
    @Bindable var tab: WorkspaceTab
    @Bindable var node: SplitNode

    var body: some View {
        switch node.kind {
        case .leaf(let pane):
            PaneHost(pane: pane, tab: tab)
        case .branch(let direction, let first, let second):
            if direction == .horizontal {
                HSplitView {
                    SplitContainer(tab: tab, node: first)
                    SplitContainer(tab: tab, node: second)
                }
            } else {
                VSplitView {
                    SplitContainer(tab: tab, node: first)
                    SplitContainer(tab: tab, node: second)
                }
            }
        }
    }
}

/// Hosts one pane's surface, with a focus ring when the tab is split and a
/// hover ✕ to close just this pane (⌘W closes the focused one). The surface
/// tracks focus itself (mouseDown → first responder → onFocus), so we just
/// reflect it; no tap gesture (that would steal clicks from selection).
private struct PaneHost: View {
    let pane: TerminalPane
    @Bindable var tab: WorkspaceTab
    @State private var hovering = false

    var body: some View {
        GhosttySurfaceHost(surface: pane.surface)
            .id(pane.id)
            .frame(minWidth: 120, maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
            .overlay {
                if !tab.isSinglePane && tab.focusedPaneID == pane.id {
                    Rectangle()
                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                // The way OUT of a split — visible on hover, per pane.
                if !tab.isSinglePane && hovering {
                    Button { tab.close(paneID: pane.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ShioTheme.textSecondary)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(ShioTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(ShioTheme.line2, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close this pane (⌘W when focused)")
                    .padding(6)
                }
            }
            .onHover { hovering = $0 }
            .onAppear {
                // Click-to-focus: the surface tells the tab when it's focused.
                pane.surface.onFocus = { [weak tab] in tab?.focusedPaneID = pane.id }
            }
            // Drive first-responder from the model so the focused pane (new
            // split, switched tab) gets the keyboard deterministically.
            .onChange(of: tab.focusedPaneID, initial: true) { _, focused in
                guard focused == pane.id else { return }
                DispatchQueue.main.async { pane.surface.window?.makeFirstResponder(pane.surface) }
            }
    }
}

