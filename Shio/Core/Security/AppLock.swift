import Foundation
import LocalAuthentication

/// Static helpers for Shio's biometric app-lock. All state lives in
/// SwiftUI views (`@AppStorage` for the toggle, `@State` for the lock
/// flag in `RootView`) — there is intentionally no observable singleton
/// here, because mixing `@MainActor` + `@Observable` + singletons turned
/// out to deadlock the app on first launch on iOS 26 device builds.
enum AppLock {

    static let defaultsKey = "shio.security.appLockEnabled"

    static var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    /// Human-readable label for whichever biometric method this device
    /// supports (or "passcode" as the fallback wording).
    static var methodLabel: String {
        switch biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "device passcode"
        }
    }

    /// Runs the biometric prompt. Returns true on success, false on any
    /// failure (including user cancel). Suitable for both the Settings
    /// confirmation flow and the unlock overlay.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            print("[shio] AppLock: canEvaluatePolicy false: \(error?.localizedDescription ?? "unknown")")
            return false
        }
        do {
            print("[shio] AppLock: calling evaluatePolicy")
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            print("[shio] AppLock: evaluatePolicy returned \(ok)")
            return ok
        } catch {
            print("[shio] AppLock: evaluatePolicy threw \(error)")
            return false
        }
    }
}
