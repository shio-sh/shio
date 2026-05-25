import Foundation
import CryptoKit

/// Encodes an Ed25519 public key in the OpenSSH `authorized_keys` line
/// format that SSH servers expect:
///
///     ssh-ed25519 <base64-encoded-blob> <comment>
///
/// The blob is the SSH wire format for the key — a length-prefixed
/// algorithm name followed by a length-prefixed 32-byte public key.
///
/// Spec: RFC 4253 §6.6 (data type representations) + draft-bjh21-ssh-ed25519.
enum OpenSSHFormatter {

    /// The comment appended after the key. Useful for users grepping
    /// their `~/.ssh/authorized_keys` later to see where this came from.
    private static let defaultComment = "shio@iphone"

    /// Returns the full `authorized_keys` line — algorithm, base64 blob,
    /// and comment — ready to paste on the remote Mac.
    static func authorizedKeysLine(
        publicKey: Curve25519.Signing.PublicKey,
        comment: String = defaultComment
    ) -> String {
        let blob = wireFormat(publicKey: publicKey)
        let b64 = blob.base64EncodedString()
        return "ssh-ed25519 \(b64) \(comment)"
    }

    /// The one-liner the user can paste into Terminal on their Mac to
    /// install the key. Quoted so shell metacharacters in the key are inert.
    static func installCommand(publicKey: Curve25519.Signing.PublicKey) -> String {
        let line = authorizedKeysLine(publicKey: publicKey)
        // Single-quote-safe: ed25519 base64 has no single quotes, so this
        // is robust without escaping.
        return "mkdir -p ~/.ssh && echo '\(line)' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    }

    // MARK: - SSH wire format

    /// SSH wire format for an Ed25519 public key:
    ///
    ///     uint32 algName.length
    ///     bytes  "ssh-ed25519"
    ///     uint32 publicKey.length (always 32 for Ed25519)
    ///     bytes  publicKey
    ///
    /// All lengths are big-endian.
    static func wireFormat(publicKey: Curve25519.Signing.PublicKey) -> Data {
        let algName = Data("ssh-ed25519".utf8)
        let keyBytes = publicKey.rawRepresentation

        var blob = Data()
        blob.appendBigEndianUInt32(UInt32(algName.count))
        blob.append(algName)
        blob.appendBigEndianUInt32(UInt32(keyBytes.count))
        blob.append(keyBytes)
        return blob
    }
}

private extension Data {
    /// Appends a 4-byte big-endian unsigned integer.
    mutating func appendBigEndianUInt32(_ value: UInt32) {
        var beValue = value.bigEndian
        Swift.withUnsafeBytes(of: &beValue) { buffer in
            append(contentsOf: buffer)
        }
    }
}
