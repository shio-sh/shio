import SwiftUI

/// Agents tab. A live, cross-project list of every agent Shio sees running in
/// your open sessions, with the one blocked on you floated to the top. Tap to
/// jump straight into that session's terminal.
///
/// State comes from output-watching (`AgentStateStore`), so it only covers
/// sessions that are currently open in the app. The Phase 6 away-watcher
/// extends this to agents you're not actively connected to.
struct AgentsView: View {
    private let store = SessionStore.shared
    private let agents = AgentStateStore.shared
    @State private var showingTerminal = false

    var body: some View {
        NavigationStack {
            Group {
                let ids = agents.liveSessionIDs
                if ids.isEmpty {
                    emptyState
                } else {
                    List(ids, id: \.self) { id in
                        if let session = store.sessions.first(where: { $0.id == id }),
                           let snapshot = agents.snapshot(for: id) {
                            Button {
                                Haptics.tap()
                                store.switchTo(session)
                                showingTerminal = true
                            } label: {
                                AgentRow(title: session.displayName, snapshot: snapshot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ShioColor.Chrome.background)
            .navigationTitle("Agents")
            .fullScreenCover(isPresented: $showingTerminal) {
                TerminalScene()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ShioSpace.lg) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(ShioColor.Text.secondary)
            Text("No agents running")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)
            Text("Start a coding agent in any session — Claude Code, Codex, or anything else — and it shows up here, so you can see at a glance which one needs you.")
                .font(ShioFont.body)
                .foregroundStyle(ShioColor.Text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioColor.Chrome.background)
    }
}

private struct AgentRow: View {
    let title: String
    let snapshot: AgentSnapshot

    var body: some View {
        HStack(spacing: ShioSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.agentName ?? "Agent")
                    .font(ShioFont.bodyEmphasis)
                    .foregroundStyle(ShioColor.Text.primary)
                Text(title)
                    .font(ShioFont.Mono.inline)
                    .foregroundStyle(ShioColor.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(label)
                .font(ShioFont.footnote)
                .foregroundStyle(tint)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShioColor.Text.tertiary)
        }
        .padding(.vertical, ShioSpace.xs)
    }

    private var icon: String {
        switch snapshot.activity {
        case .waiting:  return "bell.badge.fill"
        case .running:  return "circle.dotted"
        case .finished: return "checkmark.circle"
        case .none:     return "sparkles"
        }
    }

    private var label: String {
        switch snapshot.activity {
        case .waiting:  return "Needs you"
        case .running:  return "Working…"
        case .finished: return "Finished"
        case .none:     return ""
        }
    }

    private var tint: Color {
        switch snapshot.activity {
        case .waiting:  return .orange
        case .running:  return ShioColor.Text.secondary
        case .finished: return .green
        case .none:     return ShioColor.Text.tertiary
        }
    }
}
