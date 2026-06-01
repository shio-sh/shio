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

/// Renders a tab's split tree: a leaf hosts its surface; a branch lays out its
/// two children with a draggable divider.
struct SplitContainer: View {
    @Bindable var tab: WorkspaceTab
    @Bindable var node: SplitNode

    var body: some View {
        switch node.kind {
        case .leaf(let pane):
            PaneHost(pane: pane, tab: tab)
        case .branch(let direction, let first, let second):
            SplitLayout(direction: direction, ratio: $node.ratio) {
                SplitContainer(tab: tab, node: first)
            } second: {
                SplitContainer(tab: tab, node: second)
            }
        }
    }
}

/// Hosts one pane's surface, with a focus ring when the tab is split. The
/// surface tracks focus itself (mouseDown → first responder → onFocus), so we
/// just reflect it; no tap gesture (that would steal clicks from selection).
private struct PaneHost: View {
    let pane: TerminalPane
    @Bindable var tab: WorkspaceTab

    var body: some View {
        GhosttySurfaceHost(surface: pane.surface)
            .id(pane.id)
            .overlay {
                if !tab.isSinglePane && tab.focusedPaneID == pane.id {
                    Rectangle()
                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
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

/// A two-pane layout with a draggable divider. Ratio is the fraction given to
/// the first child; each pane keeps a minimum size.
private struct SplitLayout<First: View, Second: View>: View {
    let direction: SplitDirection
    @Binding var ratio: CGFloat
    @ViewBuilder var first: First
    @ViewBuilder var second: Second

    private let thickness: CGFloat = 6
    private let minPane: CGFloat = 60
    private let space = "split"

    var body: some View {
        GeometryReader { geo in
            let isSideBySide = direction == .horizontal
            let total = isSideBySide ? geo.size.width : geo.size.height
            let firstLen = min(max(minPane, ratio * total), total - minPane - thickness)
            let secondLen = max(minPane, total - firstLen - thickness)

            Group {
                if isSideBySide {
                    HStack(spacing: 0) {
                        first.frame(width: firstLen)
                        divider(isSideBySide: true, total: total)
                        second.frame(width: secondLen)
                    }
                } else {
                    VStack(spacing: 0) {
                        first.frame(height: firstLen)
                        divider(isSideBySide: false, total: total)
                        second.frame(height: secondLen)
                    }
                }
            }
            .coordinateSpace(name: space)
        }
    }

    /// The draggable divider — the only resize surface, so terminal selection
    /// in the panes is never hijacked.
    private func divider(isSideBySide: Bool, total: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: isSideBySide ? thickness : nil,
                   height: isSideBySide ? nil : thickness)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    (isSideBySide ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .named(space))
                    .onChanged { value in
                        guard total > 0 else { return }
                        let pos = isSideBySide ? value.location.x : value.location.y
                        ratio = min(0.9, max(0.1, pos / total))
                    }
            )
    }
}
