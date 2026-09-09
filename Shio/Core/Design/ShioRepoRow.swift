import SwiftUI

/// One repo's standing terminal inside the dashboard's repos card — shared by
/// the Mac and iPad bentos: name, then a quiet git-state second line. Context
/// menus are the caller's. Hover affordances are a no-op on touch.
struct ShioRepoRow: View {
    let row: RepoRowVM
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text("⎇").font(.system(size: 12, design: .monospaced)).foregroundStyle(ShioTheme.textTertiary)
                Text(row.name).font(.system(size: 13)).foregroundStyle(ShioTheme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                if hovering {
                    Text(row.isPlaced ? "open ›" : "set up here ›")
                        .font(.system(size: 12)).foregroundStyle(ShioTheme.textSecondary)
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

    private var secondLine: some View {
        let m = GitLineFormatter.make(row.git, stale: row.gitStale, placed: row.isPlaced)
        return HStack(spacing: 12) {
            ShioGitStatusLine(model: m, cleanMark: "clean")
            Spacer(minLength: 0)
            // An unplaced repo has no machine to name — saying one would be a lie.
            if !row.machines.isEmpty {
                Text(row.machines).foregroundStyle(ShioTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .monospacedDigit()
    }
}
