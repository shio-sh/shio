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

    // NB: every stored attribute is optional or has a default, and the
    // `projects` inverse uses `.nullify` (not `.cascade`) — both are CloudKit
    // requirements, so flipping HostStore to `cloudKitDatabase: .automatic`
    // (the Apple-account batch) syncs Host/Project across devices without a
    // schema change. Defaults are harmless locally; the initializer still sets
    // real values.

    // MARK: - Identity

    /// Display name. For Tailscale hosts this is auto-derived from MagicDNS.
    var name: String = ""

    /// Hostname or IP. For Tailscale: MagicDNS hostname (e.g. mymac.tail-scale.ts.net).
    var hostname: String = ""

    /// SSH port. Defaults to 22.
    var port: Int = 22

    /// Remote username.
    var username: String = ""

    /// Kind — controls which UI surfaces show this host.
    var kindRaw: String = Kind.tailscale.rawValue

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .tailscale }
        set { kindRaw = newValue.rawValue }
    }

    // MARK: - Persistence (per-host)

    var persistenceModeRaw: String = PersistenceMode.tmuxAutoResume.rawValue

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
    var createdAt: Date = Date()
    var lastConnectedAt: Date?

    /// Projects (repos) the user works on this host. `.nullify` (not `.cascade`)
    /// — CloudKit doesn't support cascade. Deleting a host orphans its projects
    /// (host becomes nil) rather than deleting them.
    @Relationship(deleteRule: .nullify, inverse: \Project.host)
    var projects: [Project] = []

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
    ///
    /// Auth selection (audit finding #2 — don't silently mint a key as a
    /// side effect of trying to connect):
    ///
    /// - `password != nil` → password auth.
    /// - `password == nil` and Shio has a generated key → `.shioKey`.
    /// - `password == nil` and no key yet → `.unconfigured`. SSHClient
    ///   surfaces a clear `sshKeyMissing` error pointing the user at
    ///   Settings → SSH Key, instead of attempting publickey auth with
    ///   a freshly minted key the Mac has never seen.
    func makeClientConfiguration(password: String? = nil) -> SSHClient.Configuration {
        let auth: SSHClient.Authentication
        if let password {
            auth = .password(password)
        } else if KeyManager.hasKey() {
            auth = .shioKey
        } else {
            auth = .unconfigured
        }
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
