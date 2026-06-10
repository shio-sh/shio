import Foundation
import Security

/// Remembers SSH key passphrases in the Keychain so a key the user has unlocked
/// once stays unlocked across launches — the same convenience macOS Terminal and
/// `ssh` offer via the login keychain. Keyed by the key file's path; the value
/// is the passphrase. A stale entry (the file was re-encrypted with a new
/// passphrase) is cleared on the next failed load so it self-heals.
///
/// Nothing here is ever logged. On iOS there are no `~/.ssh` keys, so this is
/// simply never exercised.
enum SSHPassphraseStore {
    private static let service = "sh.shio.ssh.key-passphrase"

    private static func baseQuery(forKeyAt url: URL) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: url.path,
        ]
    }

    static func passphrase(forKeyAt url: URL) -> String? {
        var query = baseQuery(forKeyAt: url)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func save(_ passphrase: String, forKeyAt url: URL) {
        SecItemDelete(baseQuery(forKeyAt: url) as CFDictionary)
        var add = baseQuery(forKeyAt: url)
        add[kSecValueData as String] = Data(passphrase.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func clear(forKeyAt url: URL) {
        SecItemDelete(baseQuery(forKeyAt: url) as CFDictionary)
    }
}
