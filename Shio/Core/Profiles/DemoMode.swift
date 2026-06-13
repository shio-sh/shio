import Foundation

/// Runtime switch for the screenshot/demo build. Flipped on by the **"Shio Demo"**
/// and **"ShioMac Demo"** schemes (which set `SHIO_DEMO=1` in the run
/// environment) — NEVER in a shipping build.
///
/// When active the app boots an **in-memory, CloudKit-OFF** store seeded with
/// curated easter-egg data (see `DemoSeed`). That isolation is the whole point:
/// demo content can never touch, overwrite, or sync into a real account, and the
/// real on-disk store + git cache are left untouched.
enum DemoMode {
    static let isActive: Bool = ProcessInfo.processInfo.environment["SHIO_DEMO"] == "1"
}
