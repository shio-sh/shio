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
    }

    struct ParseError: Error { let reason: String }

    /// The default identity files `ssh` tries, in order of preference.
    private static let candidates = ["id_ed25519", "id_ecdsa", "id_rsa"]

    static func load() -> LoadResult {
        var keys: [NIOSSHPrivateKey] = []
        var skipped: [String] = []
        let sshDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")

        for name in candidates {
            let url = sshDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            do {
                if let key = try parseOpenSSHPrivateKey(text) {
                    keys.append(key)
                }
            } catch let e as ParseError {
                skipped.append("\(name) — \(e.reason)")
            } catch {
                skipped.append("\(name) — couldn't read")
            }
        }
        return LoadResult(keys: keys, skipped: skipped)
    }

    /// Parse an unencrypted OpenSSH private key. Returns nil for formats we
    /// don't handle (legacy PEM / PKCS8); throws ParseError for OpenSSH keys we
    /// recognize but can't use (passphrase, RSA).
    static func parseOpenSSHPrivateKey(_ pem: String) throws -> NIOSSHPrivateKey? {
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
        _ = try r.lenPrefixed()              // kdfname
        _ = try r.lenPrefixed()              // kdfoptions
        guard cipher == "none" else {
            throw ParseError(reason: "passphrase-protected (load it into ssh-agent)")
        }
        guard try r.uint32() == 1 else { throw ParseError(reason: "multiple keys") }
        _ = try r.lenPrefixed()              // public-key blob

        // Private section — plaintext because cipher == none.
        var p = Reader(try r.lenPrefixed())
        _ = try p.uint32()                   // checkint1
        _ = try p.uint32()                   // checkint2
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
