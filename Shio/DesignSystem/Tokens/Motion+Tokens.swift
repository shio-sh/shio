import SwiftUI
import UIKit

/// Shio motion tokens — mirrors `docs/design-tokens.md` §6.
enum ShioMotion {

    // MARK: - Easing

    static let standard = Animation.timingCurve(0.32, 0.72, 0.0, 1.0, duration: durationStandard)
    static let enter    = Animation.timingCurve(0.0,  0.0, 0.2, 1.0, duration: durationStandard)
    static let exit     = Animation.timingCurve(0.4,  0.0, 1.0, 1.0, duration: durationStandard)

    static let springGentle = Animation.spring(response: 0.5,  dampingFraction: 0.85)
    static let springSnappy = Animation.spring(response: 0.32, dampingFraction: 0.80)

    // MARK: - Duration (seconds)

    static let durationInstant:    TimeInterval = 0
    static let durationFast:       TimeInterval = 0.150
    static let durationStandard:   TimeInterval = 0.240
    static let durationSlow:       TimeInterval = 0.400
    static let durationDeliberate: TimeInterval = 0.600
}

@MainActor
enum ShioHaptic {
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred()  }
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy()   { UIImpactFeedbackGenerator(style: .heavy).impactOccurred()  }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error)   }
}
