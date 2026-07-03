import Testing
import CryptoKit
@testable import Shio

/// TOFU pinning's two failure modes are silent: the fingerprint Mirror going
/// stale after an NIOSSH bump (→ pinning dies app-wide), and pin-store
/// corruption. These are the CI alarms.
struct HostKeyPinningTests {

    // MARK: The fingerprint must keep working across NIOSSH bumps

    @Test func ed25519KeysFingerprint() {
        let key = Curve25519.Signing.PrivateKey()
        let fp = HostKeyFingerprintProbe.ed25519(key)
        #expect(fp != nil, "NIOSSH internals changed — hostKeyFingerprint's Mirror is stale and TOFU is silently dead")
        #expect(fp?.hasPrefix("v1:") == true)
        // Stable: the same key always fingerprints the same.
        #expect(HostKeyFingerprintProbe.ed25519(key) == fp)
    }

    @Test func p256KeysFingerprint() {
        let key = P256.Signing.PrivateKey()
        let fp = HostKeyFingerprintProbe.p256(key)
        #expect(fp != nil)
        #expect(HostKeyFingerprintProbe.p256(key) == fp)
    }

    @Test func distinctKeysGetDistinctFingerprints() {
        #expect(HostKeyFingerprintProbe.ed25519() != HostKeyFingerprintProbe.ed25519())
        #expect(HostKeyFingerprintProbe.ed25519() != HostKeyFingerprintProbe.p256())
    }

    // MARK: Pin store round-trip (uses a .invalid host, cleaned up after)

    @Test func pinForgetRoundTrip() {
        let hostPort = "tofu-test.invalid:2222"
        #expect(ShioKnownHosts.fingerprint(for: hostPort) == nil)
        ShioKnownHosts.pin("v1:abc", for: hostPort)
        #expect(ShioKnownHosts.fingerprint(for: hostPort) == "v1:abc")
        ShioKnownHosts.pin("v1:def", for: hostPort)
        #expect(ShioKnownHosts.fingerprint(for: hostPort) == "v1:def")
        ShioKnownHosts.forget(hostPort)
        #expect(ShioKnownHosts.fingerprint(for: hostPort) == nil)
    }
}
