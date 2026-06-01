import SwiftUI

/// One tab in the Mac terminal workspace. Wraps the surface-bearing thing —
/// a plain local shell, a local Project session, or an SSH session — behind a
/// uniform title + surface so the tab strip and detail pane don't care which.
@MainActor
final class WorkspaceTab: Identifiable {
    let id = UUID()
    var title: String

    enum Content {
        case shell(GhosttyMacSurface)         // plain local login shell
        case project(MacLocalProjectSession)  // local invisible-tmux project
        case ssh(MacSSHSession)               // remote / host session
    }
    let content: Content

    init(content: Content, title: String) {
        self.content = content
        self.title = title
    }

    var surface: GhosttyMacSurface {
        switch content {
        case .shell(let s):   return s
        case .project(let p): return p.surface
        case .ssh(let s):     return s.surface
        }
    }

    /// SF Symbol hinting the tab's kind.
    var icon: String {
        switch content {
        case .shell:   return "terminal"
        case .project: return "folder.fill"
        case .ssh:     return "desktopcomputer"
        }
    }

    func stop() async {
        switch content {
        case .shell:          break          // surface freed on deinit
        case .project(let p): await p.stop()
        case .ssh(let s):     await s.stop()
        }
    }
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
            // Re-create the host when the selection changes so the new tab's
            // surface becomes first responder. Surfaces survive tab switches
            // because the tabs (not the view) own them.
            if let tab = model.selectedTab {
                GhosttySurfaceHost(surface: tab.surface).id(tab.id)
            } else {
                // Closing the last tab lands here — an intentional empty state,
                // never a blank pane (which read as "the app closed").
                EmptyTerminalState { model.newLocalTab() }
            }
        }
        .onAppear { model.ensureTerminalTab() }
    }
}

/// Shown when no tab is open (e.g. you closed the last one). Clearly the
/// terminal area at rest, with a one-tap way back in.
private struct EmptyTerminalState: View {
    let newTab: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("塩")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No terminal open")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.secondary)
            Button(action: newTab) {
                Label("New Tab", systemImage: "plus")
            }
            Text("⌘T")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
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
        .frame(height: 28)
        .background(.bar)
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
            // Reserve the close-button slot so the title doesn't shift on hover.
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 12)
            .opacity(hovering || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: 180)
        .background(isSelected ? Color.primary.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}
