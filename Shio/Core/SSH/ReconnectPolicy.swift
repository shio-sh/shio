import Foundation

/// The reconnect rules both platforms share — extracted from the proven iOS
/// `SessionViewModel` machine so the Mac's mirror of it can't drift. Pure
/// (no state, no side effects), so the table is unit-tested directly.
enum ReconnectPolicy {

    /// Maximum attempts before giving up. Six ≈ 31s of exponential backoff —
    /// plenty for a brief tunnel/network flap, short enough that a real
    /// outage surfaces while the user still remembers what they were doing.
    static let maxAttempts = 6

    /// Exponential backoff: 0.5, 1, 2, 4, 8, 16 seconds (capped).
    static func delayMilliseconds(forAttempt attempt: Int) -> UInt64 {
        UInt64(500 * (1 << min(max(attempt, 0), 5)))
    }

    /// Failures the user has to fix (a rejected key, a changed host key, a
    /// missing or locked local key) — retrying can't change the outcome, and
    /// backing off ~31s would only bury the actionable error.
    static func isPermanentFailure(_ error: any Error) -> Bool {
        guard let ssh = error as? SSHClient.SSHError else { return false }
        switch ssh {
        case .authenticationFailed, .hostKeyChanged, .sshKeyMissing,
             .noAuthenticationConfigured, .noUsableKey, .passphraseRequired,
             .keychainUnavailable, .keychainFailed:
            return true
        default:
            return false
        }
    }
}
