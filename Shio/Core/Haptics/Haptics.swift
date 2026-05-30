import UIKit

/// Centralized haptic feedback API. Centralizing it means we can:
///   - keep feedback consistent across the app
///   - prepare generators ahead of time (UIFeedbackGenerator wants a
///     `prepare()` call before fire to minimize latency)
///   - mute everything from one place if we ever add a "reduce haptics"
///     setting in Settings
@MainActor
enum Haptics {

    private static let selection = UISelectionFeedbackGenerator()
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let success = UINotificationFeedbackGenerator()

    /// A soft "tick" — for keyboard taps, session switches, picker
    /// selections. The default haptic for "I touched a discrete control."
    static func tap() {
        selection.selectionChanged()
        selection.prepare()  // warm up the next one
    }

    /// A slightly more substantive "thunk" — for actions that complete
    /// or commit something (save, primary-action button).
    static func light() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    /// "Something bigger happened" — for session connected/disconnected,
    /// modal dismissal, view transitions that matter.
    static func medium() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    /// Success notification (the iOS "checkmark" feel) — for successful
    /// connect, successful biometric unlock, successful key save.
    static func notifySuccess() {
        success.notificationOccurred(.success)
    }

    /// Warning notification — for non-fatal issues like "tmux missing",
    /// "host unreachable, falling back."
    static func notifyWarning() {
        success.notificationOccurred(.warning)
    }

    /// Error notification — for unexpected disconnect, failed auth,
    /// terminal that won't load.
    static func notifyError() {
        success.notificationOccurred(.error)
    }

    /// Pre-warm generators. Call once at app launch so the first haptic
    /// of the session doesn't have a perceptible latency hiccup.
    static func prepare() {
        selection.prepare()
        lightImpact.prepare()
        mediumImpact.prepare()
        success.prepare()
    }
}
