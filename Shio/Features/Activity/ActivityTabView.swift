import SwiftUI
import SwiftData

/// ⚑ Activity — the cross-project feed: every agent that needs you (answer
/// from the row), is working, or just finished, across every team and machine.
/// Linear's Inbox, for your agents.
struct ActivityTabView: View {
    /// Triage filter — the inbox pattern. Also the Agents tab's top-right
    /// control, which aligns its title with the other tabs.
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", needsYou = "Needs you", working = "Working", finished = "Finished"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .all: return "tray.full"
            case .needsYou: return "flag"
            case .working: return "circle.dotted"
            case .finished: return "checkmark.circle"
            }
        }
    }

    @Query(sort: \Project.name) private var projects: [Project]
    @State private var showingTerminal = false
    @State private var noCheckoutName: String?
    @State private var filter: Filter = .all
    private let sessionStore = SessionStore.shared

    private var items: [ActivityItem] {
        let all = ActivityFeed.items(projects: projects)
        switch filter {
        case .all:      return all
        case .needsYou: return all.filter { $0.activity == .waiting }
        case .working:  return all.filter { $0.activity == .running }
        case .finished: return all.filter { $0.activity == .finished }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    quietState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                FeedRow(item: item, jump: { jump(item) })
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShioTheme.background)
            .shioNavTitle("Agents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases) { f in
                                Label(f.rawValue, systemImage: f.systemImage).tag(f)
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(ShioTheme.textPrimary)
                    }
                    .accessibilityLabel("Filter agents")
                }
            }
            .fullScreenCover(isPresented: $showingTerminal) { TerminalScene() }
            .alert("No machine for this repo", isPresented: Binding(
                get: { noCheckoutName != nil }, set: { if !$0 { noCheckoutName = nil } })) {
                Button("OK") { noCheckoutName = nil }
            } message: {
                Text("“\(noCheckoutName ?? "")” has no checkout on a reachable machine yet.")
            }
        }
    }

    private func jump(_ item: ActivityItem) {
        if sessionStore.openOrCreate(repo: item.repo) != nil {
            showingTerminal = true
        } else {
            noCheckoutName = item.repoName
        }
    }

    private var quietState: some View {
        VStack(spacing: ShioSpace.md) {
            Spacer()
            Text("⚑")
                .font(.system(size: 34))
                .foregroundStyle(ShioTheme.textTertiary)
            Text("All quiet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ShioTheme.textPrimary)
            Text("When an agent needs you — any project, any machine — it lands here.")
                .font(.system(size: 13))
                .foregroundStyle(ShioTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One feed row: presence glyph + "Agent · repo", project + age at the right,
/// the agent's line under it, and inline Approve/Deny/Jump when it's blocked.
private struct FeedRow: View {
    let item: ActivityItem
    let jump: () -> Void

    private var dim: Bool { item.activity == .finished }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                glyph.frame(width: 14)
                Text("\(item.agentName) · \(item.repoName)")
                    .font(.system(size: 13.5))
                    .foregroundStyle(dim ? ShioTheme.textSecondary : ShioTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(trailingMeta)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            if let detail = item.detail, !detail.isEmpty {
                Text(item.activity == .waiting ? "\u{201C}\(detail)\u{201D}" : detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(item.activity == .waiting ? ShioTheme.warning : ShioTheme.textTertiary)
                    .lineLimit(2)
                    .padding(.top, 4)
                    .padding(.leading, 23)
            }
            if item.activity == .waiting {
                HStack(spacing: 7) {
                    ShioMiniButton(title: "Approve", status: .success) {
                        Haptics.medium()
                        ActivityFeed.reply(item, key: "y")
                    }
                    ShioMiniButton(title: "Deny", status: .danger) {
                        Haptics.medium()
                        ActivityFeed.reply(item, key: "n")
                    }
                    ShioMiniButton(title: "Jump ›") { jump() }
                }
                .padding(.top, 9)
                .padding(.leading, 23)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { jump() }
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }

    private var trailingMeta: String {
        item.age.isEmpty ? item.projectName : "\(item.projectName) · \(item.age)"
    }

    @ViewBuilder private var glyph: some View {
        switch item.activity {
        case .waiting:
            Text("⚑").font(.system(size: 13)).foregroundStyle(ShioTheme.warning).shioNeedsPulse()
        case .running:
            ShioBrailleSpinner(status: .info, size: 12)
        case .finished:
            Text("✓").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.success)
        case .none:
            EmptyView()
        }
    }
}
