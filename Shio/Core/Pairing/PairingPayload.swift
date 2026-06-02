import Foundation

/// The contract a Shio companion encodes into the QR it shows. The phone
/// scans it, provisions its SSH key onto the host (via `endpoint`), and
/// creates a `Host` from these fields. Versioned so the companion and the
/// app can evolve independently.
///
/// On the wire the QR carries either raw JSON or a `shio://pair?d=<base64url>`
/// deep link (so a tap on the same link works off-camera too).
struct PairingPayload: Codable, Equatable {
    /// Schema version. Bump when fields change incompatibly.
    var v: Int = 1
    /// Display name for the machine (e.g. "Amrith's MacBook").
    var name: String
    /// Address the phone should SSH to — a Tailscale IP / MagicDNS name, or
    /// a LAN/public address the companion advertised.
    var host: String
    /// SSH port.
    var port: Int = 22
    /// Login user on the host.
    var user: String
    /// Optional host-key fingerprint for trust-on-first-use pinning.
    var fingerprint: String?
    /// The companion's local pairing endpoint, e.g.
    /// `http://100.x.y.z:8730/pair`. The phone POSTs its public key here for
    /// authorization. nil → no live handshake; the app falls back to showing
    /// the install command for the user to paste.
    var endpoint: String?
    /// One-time pairing token the companion validates before authorizing.
    var token: String?
    /// The companion's stable device id. Lets the phone recognize a machine it
    /// already has from iCloud sync (the Mac's self-Host) and update it in place
    /// instead of creating a duplicate. nil for companions that don't sync.
    var deviceID: String?
}

extension PairingPayload {
    /// Parse a scanned string: either raw JSON, or a
    /// `shio://pair?d=<base64url-json>` deep link.
    static func parse(_ scanned: String) -> PairingPayload? {
        let s = scanned.trimmingCharacters(in: .whitespacesAndNewlines)

        // shio://pair?d=<base64url-encoded JSON>
        if let comps = URLComponents(string: s),
           comps.scheme == "shio", comps.host == "pair",
           let d = comps.queryItems?.first(where: { $0.name == "d" })?.value,
           let data = Data(base64URLEncoded: d),
           let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) {
            return payload
        }

        // Raw JSON.
        if let data = s.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) {
            return payload
        }

        return nil
    }
}

extension Data {
    /// Decode base64url (RFC 4648 §5: `-`/`_` instead of `+`/`/`, padding
    /// optional). Used by the `shio://pair` deep-link form.
    init?(base64URLEncoded s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}
