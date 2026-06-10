import Foundation
import CryptoKit
import NIOSSH

/// Loads the user's existing `~/.ssh` private keys so that on Mac, Shio
/// authenticates the way Terminal / `ssh` do — with the keys their servers
/// already trust — instead of forcing a separate Shio key onto every host.
///
/// iOS has no `~/.ssh`, so `load()` simply finds nothing there and the caller
/// falls back to the Shio key. No platform guards needed.
///
/// Supports the modern **OpenSSH** private-key format (`BEGIN OPENSSH PRIVATE
/// KEY`) for **ed25519** and **ecdsa-p256** keys — the common defaults. Keys
/// that are passphrase-protected, RSA, or in legacy PEM formats are skipped and
/// reported in `skipped` so the caller can explain why.
enum SystemSSHKeys {

    struct LoadResult {
        var keys: [NIOSSHPrivateKey]
        /// "filename: reason" for each key we found but couldn't use.
        var skipped: [String]
        /// Filenames of encrypted keys we *could* open if we had the passphrase —
        /// the caller prompts for one and calls `unlock(keyNamed:passphrase:)`.
        var encryptedNeedingPassphrase: [String] = []
    }

    /// `needsPassphrase` marks an encrypted key we recognize but haven't been
    /// given a (correct) passphrase for — the caller can prompt and retry.
    struct ParseError: Error {
        let reason: String
        var needsPassphrase = false
    }

    /// The default identity files `ssh` tries, in order of preference.
    private static let candidates = ["id_ed25519", "id_ecdsa", "id_rsa"]

    static var sshDirectory: URL {
        // `homeDirectoryForCurrentUser` is macOS-only; `NSHomeDirectory()` works
        // on both. On iOS it resolves to the app sandbox (no ~/.ssh), so `load()`
        // simply finds nothing there — which is exactly the intended behavior.
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".ssh")
    }

    static func load() -> LoadResult {
        var keys: [NIOSSHPrivateKey] = []
        var skipped: [String] = []
        var needPassphrase: [String] = []

        for name in candidates {
            let url = sshDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // For encrypted keys, try a passphrase we've already saved so the
            // user is never re-prompted for a key they've unlocked before.
            let cached = SSHPassphraseStore.passphrase(forKeyAt: url)
            do {
                if let key = try parseOpenSSHPrivateKey(text, passphrase: cached) {
                    keys.append(key)
                }
            } catch let e as ParseError where e.needsPassphrase {
                // A saved passphrase that no longer works → drop it and re-prompt.
                if cached != nil { SSHPassphraseStore.clear(forKeyAt: url) }
                needPassphrase.append(name)
            } catch let e as ParseError {
                skipped.append("\(name) — \(e.reason)")
            } catch {
                skipped.append("\(name) — couldn't read")
            }
        }
        return LoadResult(keys: keys, skipped: skipped, encryptedNeedingPassphrase: needPassphrase)
    }

    /// Validate a user-entered passphrase against an encrypted key and, on
    /// success, remember it so future loads don't prompt. Returns false on a
    /// wrong passphrase (or any read/parse failure) so the caller can re-ask.
    @discardableResult
    static func unlock(keyNamed name: String, passphrase: String) -> Bool {
        let url = sshDirectory.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        do {
            _ = try parseOpenSSHPrivateKey(text, passphrase: passphrase)
            SSHPassphraseStore.save(passphrase, forKeyAt: url)
            return true
        } catch {
            return false
        }
    }

    /// Parse an OpenSSH private key, decrypting it first when a `passphrase` is
    /// supplied. Returns nil for formats we don't handle (legacy PEM / PKCS8);
    /// throws ParseError for OpenSSH keys we recognize but can't use. Encrypted
    /// keys with no (or a wrong) passphrase throw `needsPassphrase` so the caller
    /// can prompt and retry.
    static func parseOpenSSHPrivateKey(_ pem: String, passphrase: String? = nil) throws -> NIOSSHPrivateKey? {
        guard pem.contains("BEGIN OPENSSH PRIVATE KEY") else {
            // Legacy -----BEGIN RSA/EC/PRIVATE KEY----- not supported here.
            return nil
        }
        let body = pem
            .replacingOccurrences(of: "-----BEGIN OPENSSH PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END OPENSSH PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let blob = Data(base64Encoded: body) else {
            throw ParseError(reason: "malformed")
        }

        var r = Reader(blob)
        guard try r.take(15) == Array("openssh-key-v1\u{0}".utf8) else {
            throw ParseError(reason: "unrecognized")
        }
        let cipher = try r.string()
        let kdfName = try r.string()
        let kdfOptions = try r.lenPrefixed()
        guard try r.uint32() == 1 else { throw ParseError(reason: "multiple keys") }
        _ = try r.lenPrefixed()              // public-key blob
        let privateSection = try r.lenPrefixed()

        // Decrypt the private section if the key is passphrase-protected.
        let plaintext: Data
        if cipher == "none" {
            plaintext = privateSection
        } else {
            guard let passphrase, !passphrase.isEmpty else {
                throw ParseError(reason: "passphrase required", needsPassphrase: true)
            }
            do {
                let decrypted = try OpenSSHKeyCipher.decrypt(
                    cipher: cipher, kdfName: kdfName, kdfOptions: kdfOptions,
                    encrypted: Array(privateSection), passphrase: passphrase)
                plaintext = Data(decrypted)
            } catch let e as OpenSSHKeyCipher.CipherError {
                // An unsupported cipher/KDF isn't a passphrase problem — report it
                // plainly so we don't prompt for a key we can't open anyway.
                throw ParseError(reason: e.reason)
            }
        }

        var p = Reader(plaintext)
        let check1 = try p.uint32()          // checkint1
        let check2 = try p.uint32()          // checkint2
        // The two check-ints match only when decryption succeeded — i.e. the
        // passphrase was right. This is OpenSSH's own integrity check.
        guard check1 == check2 else {
            throw ParseError(reason: "incorrect passphrase", needsPassphrase: true)
        }
        let keytype = try p.string()
        switch keytype {
        case "ssh-ed25519":
            _ = try p.lenPrefixed()                       // public key (32)
            let priv = try p.lenPrefixed()                // 64 = seed || public
            guard priv.count >= 32 else { throw ParseError(reason: "short key") }
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: priv.prefix(32))
            return NIOSSHPrivateKey(ed25519Key: key)
        case "ecdsa-sha2-nistp256":
            _ = try p.string()                            // curve name
            _ = try p.lenPrefixed()                       // public point
            var scalar = try p.lenPrefixed()              // private scalar (mpint)
            if scalar.count == 33, scalar.first == 0 { scalar = scalar.dropFirst() }
            guard scalar.count == 32 else { throw ParseError(reason: "bad ecdsa scalar") }
            let key = try P256.Signing.PrivateKey(rawRepresentation: scalar)
            return NIOSSHPrivateKey(p256Key: key)
        case let t where t.hasPrefix("ssh-rsa") || t.hasPrefix("rsa"):
            throw ParseError(reason: "RSA keys aren't supported — add an ed25519 key")
        default:
            throw ParseError(reason: "unsupported type \(keytype)")
        }
    }

    /// Minimal big-endian / SSH-wire reader.
    private struct Reader {
        private let bytes: [UInt8]
        private var i = 0
        init(_ d: Data) { bytes = Array(d) }

        mutating func take(_ n: Int) throws -> [UInt8] {
            guard i + n <= bytes.count else { throw ParseError(reason: "truncated") }
            defer { i += n }
            return Array(bytes[i..<i+n])
        }
        mutating func uint32() throws -> UInt32 {
            let b = try take(4)
            return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        }
        /// A `string`: uint32 length prefix + that many bytes.
        mutating func lenPrefixed() throws -> Data {
            let n = Int(try uint32())
            return Data(try take(n))
        }
        mutating func string() throws -> String {
            String(decoding: try lenPrefixed(), as: UTF8.self)
        }
    }
}
