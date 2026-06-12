import Foundation
import CryptoKit
import Security

/// Owns Shio's Ed25519 SSH key. One key per app install for now — Brick 7
/// second pass adds per-host keys if/when users ask for them.
///
/// **API split** (audit finding #4): we used to have a single
/// `currentKey()` that silently generated a key if none existed. That made
/// "tap a host to connect" cause a key to be minted as a side effect — bad
/// UX. The API is now split:
///
///  - `existingKey()` — pure load, no side effects. Returns nil if no key
///    has been generated yet. Use everywhere a key might *not* yet exist.
///  - `generateIfNeeded()` — explicit creation, called only from
///    `PublicKeyView` (the screen that shows the public key) so generation
///    is always a deliberate user-initiated act.
///  - `regenerate()` — destructive reset, also user-initiated.
///
/// **Storage**: private key (32-byte seed) lives in Keychain as a generic
/// password scoped to the app's `keychain-access-groups` entitlement. The
/// public key derives on demand — no cache needed.
enum KeyManager {

    /// Errors surfaced to callers. `SSHClient` maps these into user-visible
    /// `SSHError` cases.
    enum KeyError: LocalizedError {
        case keychainStoreFailed(OSStatus)
        case keychainLoadFailed(OSStatus)
        case keychainDeleteFailed(OSStatus)
        case keychainUnavailable(OSStatus)
        case keyDataCorrupted

        var errorDescription: String? {
            switch self {
            case .keychainStoreFailed(let s):
                return "Couldn't save the SSH key to Keychain (\(s))."
            case .keychainLoadFailed(let s):
                return "Couldn't read the SSH key from Keychain (\(s))."
            case .keychainDeleteFailed(let s):
                return "Couldn't remove the SSH key from Keychain (\(s))."
            case .keychainUnavailable:
                return "Keychain isn't available right now. Unlock your iPhone and try again."
            case .keyDataCorrupted:
                return "The SSH key stored in Keychain looks corrupted. Regenerate it from Settings."
            }
        }

        /// Convenience: is this an availability problem (pre-first-unlock,
        /// user-presence required) rather than a real failure? Callers can
        /// surface a friendlier message for these.
        var isAvailabilityIssue: Bool {
            if case .keychainUnavailable = self { return true }
            return false
        }
    }

    // Keychain coordinates. Generic password class is right for a small
    // piece of arbitrary key material on iOS.
    private static let service = "sh.shio.app.ssh"
    private static let account = "default"

    // MARK: - Read-only checks

    /// True if a key has been generated and stored. Cheap; no I/O beyond a
    /// Keychain attribute lookup.
    static func hasKey() -> Bool {
        (try? existingKey()) != nil
    }

    /// Returns the stored private key, or `nil` if none has been generated.
    /// **Never** generates a new key as a side effect.
    static func existingKey() throws -> Curve25519.Signing.PrivateKey? {
        try loadKey()
    }

    /// Returns the stored public key, or `nil` if no key has been generated.
    static func existingPublicKey() throws -> Curve25519.Signing.PublicKey? {
        try existingKey()?.publicKey
    }

    // MARK: - Explicit, user-initiated generation

    /// Generates and stores a new key if and only if no key exists. Returns
    /// the resulting key. Call this from a screen the user has deliberately
    /// reached — never as a side effect of trying to authenticate.
    @discardableResult
    static func generateIfNeeded() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try existingKey() {
            return existing
        }
        let fresh = Curve25519.Signing.PrivateKey()
        try storeKey(fresh)
        return fresh
    }

    /// Forces creation of a new key, replacing whatever was there. Any Mac
    /// using the previous public key will reject Shio until the user pastes
    /// the new one. Callers should set `markReinstallNeeded()` so the host
    /// list surfaces a banner.
    @discardableResult
    static func regenerate() throws -> Curve25519.Signing.PrivateKey {
        try? deleteKey()
        let fresh = Curve25519.Signing.PrivateKey()
        try storeKey(fresh)
        markReinstallNeeded()
        return fresh
    }

    // MARK: - Secure Enclave key (opt-in hardware key, #36)

    /// Whether Shio should offer the Secure-Enclave P-256 key for auth. Opt-in
    /// (Settings); the Ed25519 key remains the default and untouched. Enabling
    /// this changes the public key, so the host must re-authorize it.
    static var useEnclaveKey: Bool {
        get { UserDefaults.standard.bool(forKey: "shio.key.useEnclave") }
        set { UserDefaults.standard.set(newValue, forKey: "shio.key.useEnclave") }
    }

    /// Whether this device actually has a Secure Enclave (false on the iOS
    /// Simulator and on Macs without one).
    static func enclaveAvailable() -> Bool { SecureEnclave.isAvailable }

    static func hasEnclaveKey() -> Bool { (try? existingEnclaveKey()) != nil }

    /// Load the stored Secure-Enclave key (reconstructed from its opaque,
    /// device-bound `dataRepresentation`). Never generates.
    static func existingEnclaveKey() throws -> SecureEnclave.P256.Signing.PrivateKey? {
        guard let blob = try loadEnclaveBlob() else { return nil }
        do { return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) }
        catch { throw KeyError.keyDataCorrupted }
    }

    static func enclavePublicKey() throws -> P256.Signing.PublicKey? {
        try existingEnclaveKey()?.publicKey
    }

    /// Generate + store a Secure-Enclave key if none exists. The private key is
    /// non-extractable — only the Enclave can ever sign with it. Default access
    /// control (no per-use biometric) so SSH reconnects stay frictionless.
    @discardableResult
    static func generateEnclaveIfNeeded() throws -> SecureEnclave.P256.Signing.PrivateKey {
        if let existing = try existingEnclaveKey() { return existing }
        let fresh = try SecureEnclave.P256.Signing.PrivateKey()
        try storeEnclaveBlob(fresh.dataRepresentation)
        return fresh
    }

    @discardableResult
    static func regenerateEnclave() throws -> SecureEnclave.P256.Signing.PrivateKey {
        try? deleteEnclaveBlob()
        let fresh = try SecureEnclave.P256.Signing.PrivateKey()
        try storeEnclaveBlob(fresh.dataRepresentation)
        markReinstallNeeded()
        return fresh
    }

    private static let enclaveService = "sh.shio.app.ssh.enclave"

    private static func enclaveQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: enclaveService,
         kSecAttrAccount as String: account]
    }

    private static func loadEnclaveBlob() throws -> Data? {
        var query = enclaveQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw KeyError.keychainUnavailable(status)
        default: throw KeyError.keychainLoadFailed(status)
        }
    }

    private static func storeEnclaveBlob(_ data: Data) throws {
        try? deleteEnclaveBlob()
        var attrs = enclaveQuery()
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                throw KeyError.keychainUnavailable(status)
            }
            throw KeyError.keychainStoreFailed(status)
        }
    }

    private static func deleteEnclaveBlob() throws {
        let status = SecItemDelete(enclaveQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyError.keychainDeleteFailed(status)
        }
    }

    // MARK: - Reinstall-needed signal

    private static let reinstallFlagKey = "shio.key.needsReinstallOnMacs"

    /// Flag set by `regenerate()`. Read by `HostListView`
    /// to show a "your hosts need the new key" banner. Cleared by the user
    /// dismissing that banner.
    static var needsReinstall: Bool {
        get { UserDefaults.standard.bool(forKey: reinstallFlagKey) }
    }

    static func markReinstallNeeded() {
        UserDefaults.standard.set(true, forKey: reinstallFlagKey)
    }

    static func clearReinstallNeeded() {
        UserDefaults.standard.set(false, forKey: reinstallFlagKey)
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
            guard let data = item as? Data else { throw KeyError.keyDataCorrupted }
            do {
                return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
            } catch {
                throw KeyError.keyDataCorrupted
            }
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw KeyError.keychainUnavailable(status)
        default:
            throw KeyError.keychainLoadFailed(status)
        }
    }

    private static func storeKey(_ key: Curve25519.Signing.PrivateKey) throws {
        try? deleteKey()

        var attrs = baseQuery()
        attrs[kSecValueData as String]   = key.rawRepresentation
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = false

        let status = SecItemAdd(attrs as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecInteractionNotAllowed, errSecAuthFailed:
            throw KeyError.keychainUnavailable(status)
        default:
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
