import SwiftUI
import SwiftData

/// THE rail — Shio's Slack frame on macOS. The project (team) switcher sits at
/// the top; AGENTS (presence), SHELLS (loose per-machine terminals) and REPOS
/// (each repo's standing conversation) are the live groups; Machines & Files
/// are quiet utility rows at the bottom; 塩 signs the foot. The traffic lights
/// and the ◧ toggle float above the rail at window level (MacShell owns them).
struct MacRail: View {
    @Bindable var model: MacTerminalModel
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Host.name) private var hosts: [Host]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clearance for the traffic lights band above the switcher row.
            Color.clear.frame(height: 50)

            // ONE trailing axis: the toggle's glyph, the section-header +s and
            // the row meta all right-align 20pt off the rail edge, whatever
            // the copy on the left is doing. (The 28pt hover box is wider
            // than its glyph — hence the asymmetric inset.)
            HStack(spacing: 2) {
                switcher
                MacRailToggleButton(model: model)
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)

            Rectangle().fill(ShioTheme.line)
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    groups
                }
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }

            utility

            Text("塩 shio")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
                .padding(.leading, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .frame(width: 252)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ShioTheme.rail)
        .onAppear { ensureSelection() }
        .onChange(of: projects.count) { _, _ in ensureSelection() }
    }

    // MARK: switcher (team)

    @ViewBuilder private var switcher: some View {
        if let project = model.selectedProject {
            RailSwitcherButton(name: project.name) {
                model.showingProjectMenu.toggle()
            }
        } else {
            // No projects yet — the switcher slot is the one quiet action.
            RailSwitcherButton(name: "New project…", mark: "+", muted: true) {
                model.showingAddProject = true
            }
        }
    }

    // MARK: groups

    @ViewBuilder private var groups: some View {
        let rows = model.selectedProject.map { ProjectRows.rows(for: $0) } ?? []
        let live = rows.filter { $0.agent != .none }

        // Empty-states law: AGENTS only exists while presence is live.
        if !live.isEmpty {
            railHeader("agents")
            ForEach(live) { agentRow($0) }
        }

        railHeader("shells", add: { model.newLocalTab() }, help: "New shell on this Mac (⌘T)")
            .padding(.top, live.isEmpty ? 0 : 6)
        ForEach(shellTabs) { ShellRailRow(model: model, tab: $0) }

        if let project = model.selectedProject {
            railHeader("repos", add: { model.addRepoToProject = project },
                       help: "Add a repo to \(project.name)")
                .padding(.top, 6)
            ForEach(rows) { repoRow($0) }
        }
    }

    private var shellTabs: [WorkspaceTab] {
        model.tabs.filter(\.isShellTab)
    }

    private func agentRow(_ row: RepoRowVM) -> some View {
        RailRow(title: "\(row.agentName ?? "Agent") · \(row.name)",
                selected: isOpenConversation(row.name),
                action: { model.open(repo: row.repo) }) {
            switch row.agent {
            case .waiting:
                Text("⚑").font(.system(size: 11.5))
                    .foregroundStyle(ShioTheme.warning)
                    .shioNeedsPulse()
            case .running:
                ShioBrailleSpinner(status: .info, size: 11.5)
            case .finished:
                Text("✓").font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(ShioTheme.success)
            case .none:
                EmptyView()
            }
        } trailing: {
            if row.agent == .waiting {
                Text("needs you")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ShioTheme.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(ShioTheme.warning.opacity(0.4), lineWidth: 1))
            }
        }
    }

    private func repoRow(_ row: RepoRowVM) -> some View {
        RailRow(title: row.name,
                selected: isOpenConversation(row.name),
                action: { model.open(repo: row.repo) }) {
            Text("⎇").font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(ShioTheme.textTertiary)
        } trailing: {
            let m = GitLineFormatter.make(row.git)
            HStack(spacing: 4) {
                if m.dirty > 0 {
                    Text("\(m.dirty)").foregroundStyle(ShioTheme.warning)
                }
                if let pr = row.prs.first(where: { $0.state == "OPEN" }) {
                    if m.dirty > 0 { Text("·").foregroundStyle(ShioTheme.textTertiary) }
                    Text("PR #\(pr.number)").foregroundStyle(ShioTheme.textTertiary)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
        }
    }

    /// A repo/agent row lights up when its standing conversation is on screen.
    private func isOpenConversation(_ name: String) -> Bool {
        guard model.canvas == .conversation, let tab = model.selectedTab else { return false }
        return !tab.isShellTab && tab.title == name
    }

    // MARK: utility + chrome

    private var utility: some View {
        VStack(alignment: .leading, spacing: 2) {
            RailRow(title: "Machines", muted: true,
                    selected: model.canvas == .machines,
                    action: { model.canvas = .machines }) {
                Text("⌗").font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            } trailing: {
                Text("\(hosts.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            RailRow(title: "Files", muted: true,
                    selected: model.canvas == .files,
                    action: { model.canvas = .files }) {
                Text("▤").font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            } trailing: { EmptyView() }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    private func railHeader(_ title: String, add: (() -> Void)? = nil, help: String = "") -> some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ShioTheme.textTertiary)
            Spacer(minLength: 4)
            if let add {
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(ShioTheme.textTertiary)
                        .frame(width: 18, height: 18, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 5)
    }

    // MARK: selection

    /// Keep a project selected: the persisted one, else the most recent.
    /// Never flips the canvas — only the user's switcher click does that.
    private func ensureSelection() {
        if let sel = model.selectedProject,
           projects.contains(where: { $0.persistentModelID == sel.persistentModelID }) { return }
        let saved = UserDefaults.standard.string(forKey: MacTerminalModel.selectedProjectKey)
        model.selectedProject = projects.first { $0.name == saved } ?? projects.first
    }
}

// MARK: - Switcher button

private struct RailSwitcherButton: View {
    let name: String
    var mark: String? = nil
    var muted: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(mark ?? String(name.first ?? "•").uppercased())
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(muted ? ShioTheme.textTertiary : ShioTheme.accent)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(muted ? ShioTheme.hover : ShioTheme.accentBg)
                    )
                // Slack-style: the caret rides the name, never the far edge.
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(muted ? ShioTheme.textSecondary : ShioTheme.textPrimary)
                        .lineLimit(1)
                    if !muted {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ShioTheme.textSecondary)
                            .padding(.top, 1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? ShioTheme.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(muted ? "Add your first project" : "Switch project")
    }
}

// MARK: - Rows

/// One rail row: glyph, name, trailing meta. Hover wash, accent-tint selection.
private struct RailRow<Icon: View, Trailing: View>: View {
    let title: String
    var muted: Bool = false
    var selected: Bool = false
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon().frame(width: 13)
                Text(title)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(selected ? ShioTheme.accent
                                     : (muted ? ShioTheme.textSecondary : ShioTheme.textPrimary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                trailing()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? ShioTheme.accentBg : (hovering ? ShioTheme.hover : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A loose shell in the rail — select on click, ✕ reveals on hover.
private struct ShellRailRow: View {
    @Bindable var model: MacTerminalModel
    let tab: WorkspaceTab
    @State private var hovering = false

    var body: some View {
        let isSel = model.canvas == .conversation && model.selectedTabID == tab.id
        Button { model.focus(tab) } label: {
            HStack(spacing: 9) {
                Text("%")
                    .font(.system(size: 11.5, design: .monospaced))
                    .frame(width: 13)
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textTertiary)
                Text(tab.title)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if hovering {
                    Button { model.closeTab(tab.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ShioTheme.textTertiary)
                            .frame(width: 16, height: 16, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close shell (⌘W)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSel ? ShioTheme.accentBg : (hovering ? ShioTheme.hover : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Project menu (the ▾ dropdown)

/// The switcher's dropdown. Overlays the rail (MacShell positions it) — it
/// never pushes the layout. Every project plus "New project…"; picking one
/// lands on its dashboard.
struct MacProjectMenu: View {
    @Bindable var model: MacTerminalModel
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(projects) { project in
                item(project)
            }
            MenuRow(mark: "+", name: "New project…", current: false, action: {
                model.showingProjectMenu = false
                model.showingAddProject = true
            }, meta: { EmptyView() })
        }
        .frame(width: 232)
        .background(ShioTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(ShioTheme.line2, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 17, y: 7)
    }

    private func item(_ project: Project) -> some View {
        let current = model.selectedProject?.persistentModelID == project.persistentModelID
        return MenuRow(mark: String(project.name.first ?? "•").uppercased(),
                       name: project.name,
                       current: current,
                       action: { model.select(project: project) },
                       meta: { meta(project) })
    }

    @ViewBuilder private func meta(_ project: Project) -> some View {
        switch ProjectRows.activity(project) {
        case .waiting:
            Text("⚑").font(.system(size: 11))
                .foregroundStyle(ShioTheme.warning)
                .shioNeedsPulse()
        case .running:
            ShioBrailleSpinner(status: .info, size: 11)
        default:
            let age = shioShortAge(project.lastOpenedAt)
            if !age.isEmpty {
                Text(age)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
    }
}

private struct MenuRow<Meta: View>: View {
    let mark: String
    let name: String
    let current: Bool
    let action: () -> Void
    @ViewBuilder let meta: () -> Meta
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(mark)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(ShioTheme.hover)
                    )
                Text(name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(current ? ShioTheme.accent : ShioTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                meta()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? ShioTheme.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
