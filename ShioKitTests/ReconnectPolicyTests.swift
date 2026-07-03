import Testing
@testable import Shio

/// The shared reconnect table both platforms' state machines run on.
struct ReconnectPolicyTests {

    @Test func backoffDoublesAndCaps() {
        #expect(ReconnectPolicy.delayMilliseconds(forAttempt: 0) == 500)
        #expect(ReconnectPolicy.delayMilliseconds(forAttempt: 1) == 1000)
        #expect(ReconnectPolicy.delayMilliseconds(forAttempt: 5) == 16_000)
        #expect(ReconnectPolicy.delayMilliseconds(forAttempt: 9) == 16_000)   // capped
        #expect(ReconnectPolicy.delayMilliseconds(forAttempt: -1) == 500)     // clamped
    }

    @Test func attemptBudgetIsTheDocumentedFlapWindow() {
        // 0.5+1+2+4+8+16 ≈ 31s — the "brief network flap" budget.
        #expect(ReconnectPolicy.maxAttempts == 6)
    }

    @Test func permanentFailuresSkipTheRetryLoop() {
        #expect(ReconnectPolicy.isPermanentFailure(SSHClient.SSHError.authenticationFailed))
        #expect(ReconnectPolicy.isPermanentFailure(SSHClient.SSHError.hostKeyChanged))
        #expect(ReconnectPolicy.isPermanentFailure(SSHClient.SSHError.sshKeyMissing))
        #expect(ReconnectPolicy.isPermanentFailure(SSHClient.SSHError.passphraseRequired(["id_ed25519"])))
        #expect(ReconnectPolicy.isPermanentFailure(SSHClient.SSHError.keychainFailed("x")))
    }

    @Test func transientFailuresKeepRetrying() {
        #expect(!ReconnectPolicy.isPermanentFailure(SSHClient.SSHError.channelClosed))
        #expect(!ReconnectPolicy.isPermanentFailure(SSHClient.SSHError.connectionFailed("dns")))
        #expect(!ReconnectPolicy.isPermanentFailure(SSHClient.SSHError.notConnected))
        struct SomeOtherError: Error {}
        #expect(!ReconnectPolicy.isPermanentFailure(SomeOtherError()))
    }
}
