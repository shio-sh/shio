import SwiftUI

/// The git line — "⎇ branch ↑2 ↓1 ·3" (or clean) — rendered identically
/// wherever a repo shows its state. Staleness comes in on the model: a stale
/// cache reads "·· branch" at lowered opacity, never as live numbers.
///
/// `compact` is the trailing-cluster form (dirty count only) for rows whose
/// leading text already carries the branch.
struct ShioGitStatusLine: View {
    let model: GitLineModel
    var compact: Bool = false
    var size: CGFloat = 12
    /// The clean marker dialect: "✓" (rows) or "clean" (the Mac dashboard).
    var cleanMark: String = "✓"

    var body: some View {
        HStack(spacing: compact ? 8 : 6) {
            if !compact {
                HStack(spacing: 5) {
                    Text("⎇").foregroundStyle(ShioTheme.textTertiary)
                    Text(model.branchLabel).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(model.state == .loading || model.state == .unreachable
                                         ? ShioTheme.textTertiary : ShioTheme.textSecondary)
                }
                if model.hasTracking {
                    if model.ahead > 0 { Text("↑\(model.ahead)").foregroundStyle(ShioTheme.textSecondary) }
                    if model.behind > 0 { Text("↓\(model.behind)").foregroundStyle(ShioTheme.textSecondary) }
                }
            }
            if model.hasTracking {
                if model.dirty > 0 {
                    HStack(spacing: compact ? 3 : 5) {
                        ShioStatusDot(status: .warning, size: compact ? 5 : 6)
                        Text("\(model.dirty)").foregroundStyle(ShioTheme.warning)
                    }
                } else {
                    Text(cleanMark).foregroundStyle(ShioTheme.success)
                }
            }
        }
        .font(.system(size: size, design: .monospaced))
        .monospacedDigit()
        .opacity(model.stale ? 0.6 : 1)
    }
}
