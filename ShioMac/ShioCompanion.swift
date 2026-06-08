import SwiftUI

/// A tiny terminal-native companion for the empty-terminal state. A monospace
/// ASCII mascot that blinks, bobs gently, and every so often twinkles a `✳`
/// overhead — a quiet wink to Claude Code. Pure delight; it only appears when
/// there's no tab open, so it never gets in the way of actual work.
///
/// Driven by a single `TimelineView(.animation)`, so it pauses automatically
/// when the view is off-screen and costs nothing while you're in a terminal.
struct ShioCompanion: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    // Whimsical idle lines, rotated slowly. Terminal-flavored, never naggy.
    private let idleLines = [
        "ready when you are",
        "⌘T to begin",
        "塩  idling…",
        "the prompt is yours",
    ]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            content(t: t)
        }
    }

    @ViewBuilder
    private func content(t: TimeInterval) -> some View {
        // Blink ~120ms with a quick double-blink, every 3.2s.
        let phase = t.truncatingRemainder(dividingBy: 3.2)
        let blinking = phase < 0.12 || (phase > 0.30 && phase < 0.42)
        // Gentle breathing bob (disabled under Reduce Motion).
        let bob: CGFloat = reduceMotion ? 0 : CGFloat(sin(t * 1.3)) * 3
        // Overhead sparkle twinkles in and out (~every 7s).
        let sparkle = sin(t * 0.9)

        VStack(spacing: 14) {
            ZStack {
                Text("✳")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(MacInk.amber)
                    .opacity(max(0, Double(sparkle) - 0.55) / 0.45)
                    .scaleEffect(0.7 + 0.3 * max(0, Double(sparkle)))
                    .offset(x: 18, y: -26 + bob)

                Text(face(blinking: blinking))
                    .font(.system(size: 22, design: .monospaced).weight(.medium))
                    .foregroundStyle(MacInk.bone)
                    .multilineTextAlignment(.center)
                    .offset(y: bob)
            }
            .frame(height: 78)

            Text(idleLines[Int(t / 4.5) % idleLines.count])
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .id(Int(t / 4.5) % idleLines.count)
                .transition(.opacity)
        }
    }

    /// The mascot's face. Eyes close to dashes on a blink. Every line is the
    /// same width so the monospace box stays square.
    private func face(blinking: Bool) -> String {
        let eyes = blinking ? "—   —" : "◕   ◕"
        return """
        ╭───────╮
        │ \(eyes) │
        │   ◡   │
        ╰───────╯
        """
    }
}
