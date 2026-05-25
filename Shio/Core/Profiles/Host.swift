import Foundation
import SwiftData

/// Stored connection profile. Used for both Tailscale-discovered Macs and
/// Direct-SSH (Pro Mode) hosts — the `kind` field distinguishes them.
@Model
final class Host {

    enum Kind: String, Codable, CaseIterable {
        /// Discovered via Tailscale MagicDNS. Most users only see these.
        case tailscale
        /// Manually configured under Pro Mode.
        case directSSH
    }

    enum PersistenceMode: String, Codable, CaseIterable {
        /// Invisible tmux session — survives backgrounding (Brick 5).
        case tmuxAutoResume
        /// Mosh — survives anything (Brick 13).
        case mosh
        /// Plain SSH — stateless.
        case plain
    }

    // MARK: - Identity

    /// Display name. For Tailscale hosts this is auto-derived from MagicDNS.
    var name: String

    /// Hostname or IP. For Tailscale: MagicDNS hostname (e.g. mymac.tail-scale.ts.net).
    var hostname: String

    /// SSH port. Defaults to 22.
    var port: Int

    /// Remote username.
    var username: String

    /// Kind — controls which UI surfaces show this host.
    var kindRaw: String

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .tailscale }
        set { kindRaw = newValue.rawValue }
    }

    // MARK: - Auth

    /// Keychain reference for the private key that should be used.
    /// nil = use Shio's default key, populated in Brick 7.
    var keychainKeyRef: String?

    // MARK: - Persistence (per-host)

    var persistenceModeRaw: String

    var persistenceMode: PersistenceMode {
        get { PersistenceMode(rawValue: persistenceModeRaw) ?? .tmuxAutoResume }
        set { persistenceModeRaw = newValue.rawValue }
    }

    // MARK: - Pro Mode advanced (Direct SSH only)

    /// ProxyJump configuration string — e.g. "user@bastion.example.com:22".
    var proxyJump: String?

    /// Stored TOFU fingerprint. Set on first successful connect.
    var hostKeyFingerprint: String?

    /// Created/updated timestamps for sort + audit.
    var createdAt: Date
    var lastConnectedAt: Date?

    init(
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        kind: Kind = .tailscale,
        persistenceMode: PersistenceMode = .tmuxAutoResume
    ) {
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.kindRaw = kind.rawValue
        self.persistenceModeRaw = persistenceMode.rawValue
        self.createdAt = .now
    }
}

extension Host {
    /// Build an `SSHClient.Configuration` from this profile.
    /// Default auth is Shio's device-bound Ed25519 key (`.shioKey`). Passing
    /// a password switches to password auth — used by Pro Mode flows that
    /// elect for it.
    func makeClientConfiguration(password: String? = nil) -> SSHClient.Configuration {
        let auth: SSHClient.Authentication = password.map { .password($0) } ?? .shioKey
        return SSHClient.Configuration(
            host: hostname,
            port: port,
            username: username,
            authentication: auth,
            initialCols: 80,
            initialRows: 24
        )
    }
}
