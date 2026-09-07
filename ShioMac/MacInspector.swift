import SwiftUI

/// The GLANCE inspector — the right panel, open by default (it's almost
/// always helpful; hiding it is focus mode, ⌘I or any header's ▤). Its head
/// is EXACTLY the canvas-header height so the hairline runs as one continuous
/// line across the window (the alignment law). V1 proportions: 12px kv scale,
/// single-line rows.
struct MacInspector: View {
    @Bindable var model: MacTerminalModel

    var body: some View {
        VStack(spacing: 0) {
            head
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    groups
                }
                .padding(16)
            }
        }
        .frame(width: 272)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ShioTheme.background)
    }

    // No close button — ⌘I and every header's ▤ own the toggle (his call).
    private var head: some View {
        HStack(spacing: 4) {
            Text("GLANCE")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ShioTheme.textTertiary)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .frame(height: MacChrome.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    // MARK: groups

    @ViewBuilder private var groups: some View {
        if let project = model.selectedProject {
            let rows = ProjectRows.rows(for: project)
            let glance = ProjectRows.glance(for: project, rows: rows)

            glanceGroup(glance)

            if let repo = contextRepo(in: rows) {
                repoGroup(repo)
            }
        } else {
            Text("No project yet")
                .font(.system(size: 12))
                .foregroundStyle(ShioTheme.textTertiary)
        }
    }

    /// The repo whose terminal is on screen — the "this repo" context.
    private func contextRepo(in rows: [RepoRowVM]) -> RepoRowVM? {
        guard model.canvas == .terminal,
              let tab = model.selectedTab, !tab.isShellTab else { return nil }
        return rows.first { $0.name == tab.title }
    }

    private func glanceGroup(_ glance: ProjectGlance) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if glance.changes == 0 {
                Text("all quiet")
                    .font(.system(size: 12))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .padding(.vertical, 5)
            } else {
                kv("Changes") {
                    Text("\(glance.changes)").foregroundStyle(ShioTheme.warning)
                }
            }
            if PowerKeeper.shared.isHolding {
                Text("keeping this mac awake")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .padding(.top, 6)
            }
        }
    }

    private func repoGroup(_ repo: RepoRowVM) -> some View {
        let m = GitLineFormatter.make(repo.git)
        return VStack(alignment: .leading, spacing: 0) {
            groupHeader("this repo")
            kv("⎇ Branch") {
                Text(m.branch).foregroundStyle(ShioTheme.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if m.hasTracking {
                kv("Dirty") {
                    if m.dirty > 0 {
                        Text("\(m.dirty) file\(m.dirty == 1 ? "" : "s")").foregroundStyle(ShioTheme.warning)
                    } else {
                        Text("clean").foregroundStyle(ShioTheme.success)
                    }
                }
                if m.ahead > 0 || m.behind > 0 {
                    kv("Sync") {
                        Text([m.ahead > 0 ? "↑\(m.ahead)" : nil,
                              m.behind > 0 ? "↓\(m.behind)" : nil]
                            .compactMap(\.self).joined(separator: " "))
                            .foregroundStyle(ShioTheme.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: primitives (v1 proportions — 12px kv, never bigger)

    private func groupHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(2)
            .foregroundStyle(ShioTheme.textTertiary)
            .padding(.bottom, 8)
    }

    private func kv<V: View>(_ key: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 8) {
            Text(key).foregroundStyle(ShioTheme.textSecondary)
            Spacer(minLength: 8)
            value()
        }
        .font(.system(size: 12, design: .monospaced))
        .monospacedDigit()
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
    }
}
