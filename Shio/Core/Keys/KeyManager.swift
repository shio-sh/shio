import Foundation
import CryptoKit
import Security

/// Owns Shio's Ed25519 SSH key. One key per app install for now — Brick 7
/// second pass adds per-host keys if/when users ask for them.
///
/// **Storage model**:
/// - Private key (32-byte seed) lives in the Keychain as a generic
///   password, scoped to the app's `keychain-access-groups` entitlement.
/// - Public key is derived on demand from the private key (no need to
///   cache; it's cheap).
/// - Generation happens lazily on first `currentKey()` call.
///
/// **Note on Secure Enclave**: CryptoKit's `Curve25519.Signing.PrivateKey`
/// does *not* support Secure Enclave (that's reserved for `SecureEnclave.P256`).
/// For Brick 7 we use Keychain-backed Ed25519, which is the standard for
/// SSH clients on iOS. Apps that need Secure Enclave-only would switch to
/// ecdsa-sha2-nistp256 — out of scope here.
enum KeyManager {

    /// Errors surfaced to callers. SSHClient maps these to user-visible copy.
    enum KeyError: LocalizedError {
        case keychainStoreFailed(OSStatus)
        case keychainLoadFailed(OSStatus)
        case keychainDeleteFailed(OSStatus)
        case keyDataCorrupted

        var errorDescription: String? {
            switch self {
            case .keychainStoreFailed(let status):
                return "Couldn't save the SSH key to Keychain (\(status))."
            case .keychainLoadFailed(let status):
                return "Couldn't read the SSH key from Keychain (\(status))."
            case .keychainDeleteFailed(let status):
                return "Couldn't remove the SSH key from Keychain (\(status))."
            case .keyDataCorrupted:
                return "The SSH key stored in Keychain looks corrupted. Regenerate it from Settings."
            }
        }
    }

    // Keychain item coordinates. Generic password class is the right fit for
    // a small piece of arbitrary key material on iOS.
    private static let service = "sh.shio.app.ssh"
    private static let account = "default"

    /// Returns the current key, generating + persisting a new one on first call.
    /// Subsequent calls return the same key until `regenerate()` is called.
    @discardableResult
    static func currentKey() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try loadKey() {
            return existing
        }
        let fresh = Curve25519.Signing.PrivateKey()
        try storeKey(fresh)
        return fresh
    }

    /// Forces creation of a new key, replacing whatever was there.
    /// Any Macs using the previous public key will need the new one pasted in.
    @discardableResult
    static func regenerate() throws -> Curve25519.Signing.PrivateKey {
        try? deleteKey()
        let fresh = Curve25519.Signing.PrivateKey()
        try storeKey(fresh)
        return fresh
    }

    /// True if a key has been generated and stored.
    static func hasKey() -> Bool {
        (try? loadKey()) != nil
    }

    // MARK: - Public-facing convenience

    /// The public key, derived from the stored private key. Cheap to call;
    /// no caching required.
    static func currentPublicKey() throws -> Curve25519.Signing.PublicKey {
        try currentKey().publicKey
    }

    // MARK: - Keychain plumbing

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func loadKey() throws -> Curve25519.Signing.PrivateKey? {
        var query = baseQuery()
        query[kSecReturnData as String]  = true
        query[kSecMatchLimit as String]  = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeyError.keyDataCorrupted
            }
            do {
                return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
            } catch {
                throw KeyError.keyDataCorrupted
            }
        case errSecItemNotFound:
            return nil
        default:
            throw KeyError.keychainLoadFailed(status)
        }
    }

    private static func storeKey(_ key: Curve25519.Signing.PrivateKey) throws {
        // Delete any existing item first so we don't have to deal with
        // duplicate-attribute errors.
        try? deleteKey()

        var attrs = baseQuery()
        attrs[kSecValueData as String]   = key.rawRepresentation
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = false

        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyError.keychainStoreFailed(status)
        }
    }

    private static func deleteKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyError.keychainDeleteFailed(status)
        }
    }
}
