import Testing
import Foundation
@testable import Shio

/// The bcrypt_pbkdf port is the one piece of hand-written crypto in the app —
/// pin it to the public reference vector so a refactor can never silently
/// change what keys it derives.
struct OpenSSHKeyCipherTests {

    /// Reference vector shared by the OpenBSD regress suite and
    /// golang.org/x/crypto's bcrypt_pbkdf tests: ("password", "salt", 4 rounds).
    @Test func bcryptPBKDFMatchesReferenceVector() {
        let out = OpenSSHKeyCipher.bcryptPBKDF(
            passphrase: Array("password".utf8),
            salt: Array("salt".utf8),
            rounds: 4,
            keyLength: 32)
        let expected: [UInt8] = [
            0x5b, 0xbf, 0x0c, 0xc2, 0x93, 0x58, 0x7f, 0x1c,
            0x36, 0x35, 0x55, 0x5c, 0x27, 0x79, 0x65, 0x98,
            0xd4, 0x7e, 0x57, 0x90, 0x71, 0xbf, 0x42, 0x7e,
            0x9d, 0x8f, 0xbe, 0x84, 0x2a, 0xba, 0x34, 0xd9,
        ]
        #expect(out == expected)
    }

    @Test func derivesExactRequestedLengthDeterministically() {
        // 48 = the aes256 key+IV ask; exercises the multi-block interleaving.
        let a = OpenSSHKeyCipher.bcryptPBKDF(
            passphrase: Array("pw".utf8), salt: Array("na".utf8), rounds: 2, keyLength: 48)
        let b = OpenSSHKeyCipher.bcryptPBKDF(
            passphrase: Array("pw".utf8), salt: Array("na".utf8), rounds: 2, keyLength: 48)
        #expect(a.count == 48)
        #expect(a == b)
        // And a different passphrase diverges.
        let c = OpenSSHKeyCipher.bcryptPBKDF(
            passphrase: Array("pw2".utf8), salt: Array("na".utf8), rounds: 2, keyLength: 48)
        #expect(a != c)
    }

    /// kdfoptions = string(salt) || uint32(rounds), big-endian.
    private func kdfOptions(saltLength: Int = 16, rounds: UInt32 = 16) -> Data {
        var d = Data()
        d.append(contentsOf: [0, 0, 0, UInt8(saltLength)])
        d.append(contentsOf: [UInt8](repeating: 0xAB, count: saltLength))
        d.append(contentsOf: [UInt8((rounds >> 24) & 0xff), UInt8((rounds >> 16) & 0xff),
                              UInt8((rounds >> 8) & 0xff), UInt8(rounds & 0xff)])
        return d
    }

    @Test func unsupportedCipherIsReportedNotGuessed() {
        #expect(throws: OpenSSHKeyCipher.CipherError.self) {
            _ = try OpenSSHKeyCipher.decrypt(
                cipher: "chacha20-poly1305@openssh.com", kdfName: "bcrypt",
                kdfOptions: kdfOptions(), encrypted: [UInt8](repeating: 0, count: 32),
                passphrase: "x")
        }
    }

    @Test func unsupportedKDFIsReported() {
        #expect(throws: OpenSSHKeyCipher.CipherError.self) {
            _ = try OpenSSHKeyCipher.decrypt(
                cipher: "aes256-ctr", kdfName: "none",
                kdfOptions: kdfOptions(), encrypted: [UInt8](repeating: 0, count: 32),
                passphrase: "x")
        }
    }

    @Test func malformedKDFOptionsThrow() {
        #expect(throws: OpenSSHKeyCipher.CipherError.self) {
            _ = try OpenSSHKeyCipher.decrypt(
                cipher: "aes256-ctr", kdfName: "bcrypt",
                kdfOptions: Data([0, 0]), encrypted: [UInt8](repeating: 0, count: 32),
                passphrase: "x")
        }
    }

    @Test func misalignedCiphertextThrows() {
        #expect(throws: OpenSSHKeyCipher.CipherError.self) {
            _ = try OpenSSHKeyCipher.decrypt(
                cipher: "aes256-ctr", kdfName: "bcrypt",
                kdfOptions: kdfOptions(), encrypted: [UInt8](repeating: 0, count: 30),
                passphrase: "x")
        }
    }

    @Test func wellFormedInputDecryptsToSameLength() throws {
        // Round-trip property: CTR is length-preserving; a well-formed call
        // returns exactly the ciphertext's length (2 rounds keeps it fast).
        let plain = try OpenSSHKeyCipher.decrypt(
            cipher: "aes256-ctr", kdfName: "bcrypt",
            kdfOptions: kdfOptions(rounds: 2), encrypted: [UInt8](repeating: 0x42, count: 64),
            passphrase: "correct horse")
        #expect(plain.count == 64)
    }
}
