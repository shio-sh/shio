import SwiftUI
import SwiftData

/// The GLANCE inspector — the right panel, open by default (it's almost
/// always helpful; hiding it is focus mode, ⌘I or any header's ▤). Its head
/// is EXACTLY the canvas-header height so the hairline runs as one continuous
/// line across the window (the alignment law). V1 proportions: 12px kv scale,
/// single-line rows.
struct MacInspector: View {
    @Bindable var model: MacTerminalModel
    @Query(sort: \Skill.createdAt) private var allSkills: [Skill]

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

    private var head: some View {
        HStack(spacing: 4) {
            Text("GLANCE")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ShioTheme.textTertiary)
            Spacer(minLength: 4)
            MacHeaderIconButton(glyph: "✕", help: "Close (⌘I)") {
                model.inspectorOpen = false
            }
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

            let global = allSkills.filter { $0.isGlobal && $0.enabled }
            let scoped = allSkills.filter { $0.project?.persistentModelID == project.persistentModelID }
            if !global.isEmpty || !scoped.isEmpty {
                skillsGroup(global: global, scoped: scoped)
            }

            if project.notes?.isEmpty == false {
                memoryGroup
            }
        } else {
            Text("No project yet")
                .font(.system(size: 12))
                .foregroundStyle(ShioTheme.textTertiary)
        }
    }

    /// The repo whose conversation is on screen — the "this repo" context.
    private func contextRepo(in rows: [RepoRowVM]) -> RepoRowVM? {
        guard model.canvas == .conversation,
              let tab = model.selectedTab, !tab.isShellTab else { return nil }
        return rows.first { $0.name == tab.title }
    }

    private func glanceGroup(_ glance: ProjectGlance) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if glance.changes == 0 && glance.working == 0 && glance.needsYou == 0 && glance.prs == 0 {
                Text("all quiet")
                    .font(.system(size: 12))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .padding(.vertical, 5)
            } else {
                if glance.changes > 0 {
                    kv("Changes") {
                        Text("\(glance.changes)").foregroundStyle(ShioTheme.warning)
                    }
                }
                if glance.working > 0 || glance.needsYou > 0 {
                    kv("Agents") {
                        HStack(spacing: 5) {
                            if glance.working > 0 {
                                ShioBrailleSpinner(status: .info, size: 11)
                                Text("\(glance.working)").foregroundStyle(ShioTheme.info)
                            }
                            if glance.working > 0 && glance.needsYou > 0 {
                                Text("·").foregroundStyle(ShioTheme.textTertiary)
                            }
                            if glance.needsYou > 0 {
                                Text("⚑ \(glance.needsYou)").foregroundStyle(ShioTheme.warning)
                            }
                        }
                    }
                }
                if glance.prs > 0 {
                    kv("PRs open") {
                        Text("\(glance.prs)").foregroundStyle(ShioTheme.textPrimary)
                    }
                }
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
            if let pr = repo.prs.first(where: { $0.state == "OPEN" }) {
                ShioChip(text: "PR #\(pr.number)\(pr.isDraft ? " · draft" : "")",
                         status: pr.isDraft ? .neutral : .info)
                    .padding(.top, 8)
            }
        }
    }

    private func skillsGroup(global: [Skill], scoped: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader("skills")
            ForEach(global) { skillRow($0, scope: "global") }
            ForEach(scoped) { skillRow($0, scope: "project") }
        }
    }

    private func skillRow(_ skill: Skill, scope: String) -> some View {
        HStack(spacing: 8) {
            Text("✓").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.success)
            Text(skill.name)
                .font(.system(size: 12.5))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            ShioChip(text: scope, status: scope == "project" ? .accent : .neutral)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }

    private var memoryGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader("memory & context")
            HStack(spacing: 8) {
                Text("✎").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
                Text("Notes").font(.system(size: 12.5)).foregroundStyle(ShioTheme.textPrimary)
                Spacer(minLength: 6)
                Text("edited").font(.system(size: 11, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
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
