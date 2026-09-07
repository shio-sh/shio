import Foundation
import IOKit.ps
import Observation

/// Holds off system sleep exactly while sleep would break a promise: a device
/// is logged in over SSH (remote typing doesn't count as "user activity" to
/// macOS, so a phone session can be cut off mid-keystroke by idle sleep).
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

    /// Master switch — ON by default (this IS the remote-control promise).
    static let enabledKey = "shio.power.keepAwake"
    /// Hold on battery too — OFF by default (a real drain trade).
    static let batteryKey = "shio.power.keepAwakeOnBattery"

    /// True while the assertion is held — surfaced quietly in the UI
    /// (invisibly preventing sleep erodes trust when discovered).
    private(set) var isHolding = false

    // Internal plumbing — only `isHolding` is observed; tracking these would
    // also force `any` into the @Observable-generated source.
    @ObservationIgnored private var remoteClientPresent = false
    @ObservationIgnored private var activity: (any NSObjectProtocol)?
    @ObservationIgnored private var timer: Timer?

    private init() {}

    /// Begin polling for an attached SSH client (idempotent).
    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        Task {
            let present = await Self.remoteLoginPresent()
            self.update(remoteClientPresent: present)
        }
    }

    /// Fed by the poll loop every ~5s — which also makes power-source changes
    /// take effect within a tick.
    func update(remoteClientPresent: Bool) {
        self.remoteClientPresent = remoteClientPresent
        reevaluate()
    }

    /// Re-check the whole condition (also called when Settings toggles flip).
    func reevaluate() {
        let defaults = UserDefaults.standard
        let enabled = (defaults.object(forKey: Self.enabledKey) as? Bool) ?? true
        let powerOK = Self.onACPower || defaults.bool(forKey: Self.batteryKey)
        let want = enabled && powerOK && remoteClientPresent
        guard want != isHolding else { return }
        if want {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled, reason: "Shio: a device is attached over SSH")
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

    /// Any SSH login on this Mac right now? utmpx entries carry the remote
    /// host in parens — local terminals (console, ghostty tabs) don't.
    nonisolated private static func remoteLoginPresent() async -> Bool {
        await Task.detached(priority: .utility) {
            run("/usr/bin/who", []).contains("(")
        }.value
    }

    nonisolated private static func run(_ bin: String, _ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch { return "" }
    }
}
