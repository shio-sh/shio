import SwiftUI

// MARK: - Bento plumbing (shared by the Mac and iPad dashboards)

/// One bento row: children laid out side by side at fixed ratios, every child
/// offered the full row height — so bottoms align ("every edge lands").
struct BentoRow: Layout {
    var ratios: [CGFloat]
    var spacing: CGFloat = 14

    private func widths(total: CGFloat, count: Int) -> [CGFloat] {
        let usable = max(0, total - spacing * CGFloat(count - 1))
        let sum = ratios.reduce(0, +)
        return (0..<count).map { usable * (ratios.indices.contains($0) ? ratios[$0] : 1) / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 800
        let ws = widths(total: total, count: subviews.count)
        let h = zip(subviews, ws)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(total: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (i, sub) in subviews.enumerated() {
            sub.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                      proposal: ProposedViewSize(width: ws[i], height: bounds.height))
            x += ws[i] + spacing
        }
    }
}

/// A bento card: OUTLINE-ONLY at rest (1px hairline, 11pt radius, transparent),
/// surface fill on hover — a no-op on touch, where the outline is the look.
/// UPPERCASE mono header with an optional quiet action.
struct BentoCard<Content: View>: View {
    let title: String
    var addLabel: String? = nil
    var addAction: (() -> Void)? = nil
    /// Stretch to fill the row height (grid alignment); false = natural height.
    var stretch: Bool = true
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(ShioTheme.textTertiary)
                Spacer(minLength: 4)
                if let addLabel, let addAction {
                    Button(action: addAction) {
                        Text(addLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
            content()
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 9, trailing: 14))
        .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? ShioTheme.surface : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(ShioTheme.line2, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
