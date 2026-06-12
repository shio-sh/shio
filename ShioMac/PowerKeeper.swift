import Foundation
import IOKit.ps
import Observation

/// Holds off system sleep exactly while sleep would break a promise: a local
/// agent is working or waiting (the away-supervision chain — watcher, push,
/// approve-injection — all die if the Mac dozes), or a device is logged in
/// over SSH (remote typing doesn't count as "user activity" to macOS, so a
/// phone session can be cut off mid-keystroke by idle sleep).
///
/// Presence-scoped, never a mode: asserted when the condition starts, released
/// the moment it ends. Display sleep is untouched — the screen goes dark like
/// normal; only the machine keeps working (`caffeinate -i` semantics, via the
/// native activity API). On battery it stays out of the way unless the user
/// opts in. Honest limits: a closed lid on battery sleeps regardless.
@Observable
@MainActor
final class PowerKeeper {
    static let shared = PowerKeeper()

    /// Master switch — ON by default (this IS the away promise).
    static let enabledKey = "shio.power.keepAwake"
    /// Hold on battery too — OFF by default (a real drain trade).
    static let batteryKey = "shio.power.keepAwakeOnBattery"

    /// True while the assertion is held — surfaced quietly in the UI
    /// (invisibly preventing sleep erodes trust when discovered).
    private(set) var isHolding = false

    private var agentsActive = false
    private var remoteClientPresent = false
    private var activity: NSObjectProtocol?

    private init() {}

    /// Fed by the agent monitor every poll (≈4s) — which also makes power-
    /// source changes take effect within a tick.
    func update(agentsActive: Bool, remoteClientPresent: Bool) {
        self.agentsActive = agentsActive
        self.remoteClientPresent = remoteClientPresent
        reevaluate()
    }

    /// Re-check the whole condition (also called when Settings toggles flip).
    func reevaluate() {
        let defaults = UserDefaults.standard
        let enabled = (defaults.object(forKey: Self.enabledKey) as? Bool) ?? true
        let powerOK = Self.onACPower || defaults.bool(forKey: Self.batteryKey)
        let want = enabled && powerOK && (agentsActive || remoteClientPresent)
        guard want != isHolding else { return }
        if want {
            let reason = agentsActive
                ? "Shio: an agent is working — sleep would freeze it"
                : "Shio: a device is attached over SSH"
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled, reason: reason)
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        isHolding = want
    }

    /// AC = "unlimited time remaining". Unknown (-1, while the battery
    /// estimate recalculates) only happens ON battery, so it reads as battery.
    static var onACPower: Bool {
        IOPSGetTimeRemainingEstimate() == kIOPSTimeRemainingUnlimited
    }
}
