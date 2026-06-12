import Foundation

/// Translates NIO + Network framework error descriptions into the
/// user-visible copy Shio uses everywhere it reports a connection
/// failure. Lives in one place so `SSHClient` and `TailscaleDiagnostic`
/// surface identical wording for the same underlying problem.
///
/// Voice rules (per `docs/brand.md`):
///  - Plain, calm, never clever.
///  - Direct address ("Open the Tailscale app…").
///  - Name the specific UI element to tap.
///  - One paragraph, max ~4 bulleted causes.
enum ConnectErrorTranslator {

    /// Translate a raw error from a TCP/DNS layer (NIO or Network framework)
    /// into a user-readable explanation.
    static func translate(_ error: any Error, host: String, port: Int, connectTimeoutSeconds: Int = 10) -> String {
        // Shio's own errors already carry actionable human copy — never show
        // the bare enum case ("authenticationFailed", "eof") instead.
        if let ssh = error as? SSHClient.SSHError, let copy = ssh.errorDescription {
            return copy
        }
        let raw = String(describing: error)

        if matchesDNSFailure(raw) {
            return dnsFailureMessage(host: host)
        }

        if raw.contains("NIOConnectionError") {
            return [
                "Tried \(host):\(port) but couldn't get through. Common causes:",
                "• Your Mac is asleep or off — wake it.",
                "• Tailscale isn't running on both devices — open the Tailscale app.",
                "• Remote Login isn't enabled on the Mac — System Settings → General → Sharing → Remote Login.",
                "• The hostname is wrong — check your Mac's name on tailscale.com.",
            ].joined(separator: "\n")
        }

        if raw.contains("Connection refused") {
            return "\(host) refused the connection on port \(port). Remote Login is probably off — turn it on under System Settings → General → Sharing on your Mac."
        }
        if raw.contains("No route to host") || raw.contains("Network is unreachable") {
            return "Can't route to \(host). Make sure Tailscale is running on both your iPhone and your Mac."
        }
        if raw.contains("Operation timed out") || raw.contains("timeout") {
            return "\(host) didn't respond within \(connectTimeoutSeconds)s. The Mac may be asleep, or Tailscale may not be connecting."
        }

        return raw
    }

    /// Returns true if the error description matches a DNS resolution failure.
    /// Exposed for the diagnostic engine, which uses this to decide whether
    /// to surface the "MagicDNS isn't resolving" diagnosis specifically.
    static func matchesDNSFailure(_ raw: String) -> Bool {
        raw.contains("UnknownHost") || raw.contains("nodename nor servname")
    }

    /// The DNS failure message — broken out so the diagnostic engine can
    /// reach for it directly when its MagicDNS probe fails.
    static func dnsFailureMessage(host: String) -> String {
        let looksLikeTailscale = isTailscaleHostname(host)
        var lines = ["Couldn't find \(host) on the network."]
        if looksLikeTailscale {
            lines.append("That's a Tailscale name — and your iPhone's DNS doesn't know about it. Two things to check:")
            lines.append("• Open the Tailscale iOS app and make sure it says Connected (the toggle is on).")
            lines.append("• In the Tailscale app's settings, ensure \"Use Tailscale DNS\" is enabled.")
            lines.append("If that doesn't work, try your Mac's tailnet IP instead (it looks like 100.x.y.z and is shown next to your Mac in tailscale.com → Machines).")
        } else {
            lines.append("DNS lookup failed. Check the hostname is spelled correctly.")
        }
        return lines.joined(separator: "\n")
    }

    /// Heuristic: does this hostname look like it's served by Tailscale's
    /// MagicDNS? Used to pick Tailscale-flavored remediation copy.
    static func isTailscaleHostname(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower.hasSuffix(".ts.net") || lower.contains(".tail")
    }
}
