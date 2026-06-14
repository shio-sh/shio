import Foundation

/// Switch for the screenshot/demo build. Flipped on by the **"Shio Demo"** and
/// **"ShioMac Demo"** schemes, which build the dedicated **`Demo`
/// configuration** (`DEMO_MODE` compile flag) — NEVER a shipping build.
///
/// The flag is COMPILE-TIME, baked into the binary, so the app boots into demo
/// mode no matter how it launches — from the home screen, untethered, without
/// Xcode attached. (A scheme env var only applies when Xcode launches the
/// process with the debugger, which is why the earlier env-var approach showed
/// real data when run from the phone's home screen.) The `SHIO_DEMO` env var is
/// kept as a convenience for toggling a normal build in the simulator.
///
/// When active the app boots an **in-memory, CloudKit-OFF** store seeded with
/// curated easter-egg data (see `DemoSeed`). That isolation is the whole point:
/// demo content can never touch, overwrite, or sync into a real account, and the
/// real on-disk store + git cache are left untouched.
enum DemoMode {
    #if DEMO_MODE
    static let isActive = true
    #else
    static let isActive: Bool = ProcessInfo.processInfo.environment["SHIO_DEMO"] == "1"
    #endif
}
