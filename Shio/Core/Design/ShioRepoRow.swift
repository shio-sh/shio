import SwiftUI

/// One repo's standing terminal inside the dashboard's repos card — shared by
/// the Mac and iPad bentos: presence glyph + name + PR chip, then the live
/// second line — the agent's question with inline Approve/Deny when it needs
/// you, the working detail while it runs, or quiet git state at rest.
/// Approve/deny are injected (the Mac answers its own tmux; iOS answers over
/// the session or CloudKit); context menus are the caller's. Hover
/// affordances are a no-op on touch.
struct ShioRepoRow: View {
    let row: RepoRowVM
    let open: () -> Void
    var approve: (() -> Void)? = nil
    var deny: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                presence
                Text(row.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                if let pr = row.prs.first(where: { $0.state == "OPEN" }) {
                    ShioChip(text: "PR #\(pr.number)", status: pr.isDraft ? .neutral : .info)
                }
                if hovering {
                    Text("open ›").font(.system(size: 12)).foregroundStyle(ShioTheme.textSecondary)
                }
            }
            secondLine
        }
        .padding(.horizontal, 10).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(hovering ? ShioTheme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .onHover { hovering = $0 }
    }

    /// .finished stays quiet here — the row idles at ⎇.
    private var presence: some View {
        ShioPresenceGlyph(activity: row.agent == .finished ? .none : row.agent, size: 12)
    }

    @ViewBuilder private var secondLine: some View {
        let m = GitLineFormatter.make(row.git, stale: row.gitStale)
        HStack(spacing: 12) {
            switch row.agent {
            case .waiting:
                Text(agentLine(quoted: true))
                    .foregroundStyle(ShioTheme.warning)
                    .lineLimit(1).truncationMode(.tail)
                if let approve { ShioMiniButton(title: "Approve · y", status: .success, action: approve) }
                if let deny { ShioMiniButton(title: "Deny · n", status: .danger, action: deny) }
                Spacer(minLength: 0)
            case .running:
                HStack(spacing: 6) {
                    ShioBrailleSpinner(status: .info, size: 11)
                    Text(agentLine(quoted: false)).foregroundStyle(ShioTheme.info)
                        .lineLimit(1).truncationMode(.tail)
                }
                ShioGitStatusLine(model: m, cleanMark: "clean")
                Spacer(minLength: 0)
            default:
                ShioGitStatusLine(model: m, cleanMark: "clean")
                Spacer(minLength: 0)
                Text(row.machines).foregroundStyle(ShioTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .monospacedDigit()
    }

    private func agentLine(quoted: Bool) -> String {
        let name = row.agentName ?? "Agent"
        guard let d = row.agentDetail, !d.isEmpty else { return name }
        return quoted ? "\(name) · \u{201C}\(d)\u{201D}" : "\(name) · \(d)"
    }
}
