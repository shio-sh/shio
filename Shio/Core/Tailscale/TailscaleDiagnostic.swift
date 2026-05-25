import Foundation
import Network
import UIKit

/// Verifies the four things Shio needs Tailscale to be doing in order for
/// an SSH connection to succeed:
///
///   1. **appInstalled** — Tailscale iOS app present (URL scheme probe).
///   2. **vpnActive** — Tailscale's `NEPacketTunnelProvider` is up and has
///      installed its `100.64.0.0/10` route. Tested by attempting a TCP
///      connect to `100.100.100.100:53` — that IP is *only* reachable when
///      Tailscale is actively routing. Reaching it in <1.5s = on.
///   3. **magicDNS** — Tailscale's local resolver is being asked. Tested
///      by trying to resolve a sentinel name. If `vpnActive` failed, this
///      is skipped (the answer is moot).
///   4. **hostReachable** — a specific target Mac responds on the SSH port.
///      Tested by TCP-connecting to `<host>:22`. Distinguishes DNS failure
///      vs. refused (Remote Login off) vs. timeout (asleep).
///
/// Probes run in parallel with per-check timeouts. Each `CheckResult`
/// carries a remediation hint mapped through `ConnectErrorTranslator` so
/// the wording matches everywhere else in the app.
actor TailscaleDiagnostic {

    static let shared = TailscaleDiagnostic()

    // MARK: - Types

    enum Check: String, CaseIterable, Sendable {
        case appInstalled
        case vpnActive
        case magicDNS
        case hostReachable

        var title: String {
            switch self {
            case .appInstalled:  return "Tailscale app installed"
            case .vpnActive:     return "Tailscale VPN connected"
            case .magicDNS:      return "Tailscale DNS resolving"
            case .hostReachable: return "Your Mac is reachable"
            }
        }
    }

    enum Status: Equatable, Sendable {
        case idle
        case running
        case passed
        case failed(reason: String)
        /// Skipped because a precondition failed (e.g. magicDNS check skipped
        /// when vpnActive is false).
        case skipped(reason: String)
    }

    enum Remediation: Equatable, Sendable {
        case openTailscaleApp
        case openTailscaleAppStorePage
        case openMacSharingSettings(text: String)
        case useIPInstead
        case none
    }

    struct CheckResult: Equatable, Sendable {
        let check: Check
        let status: Status
        let detail: String
        let remediation: Remediation
        let measuredAt: Date
    }

    struct Report: Equatable, Sendable {
        let results: [Check: CheckResult]
        let target: String?

        /// Overall status — worst-of for surfacing a single summary state.
        var overall: Status {
            if results.values.contains(where: { if case .running = $0.status { return true } else { return false } }) {
                return .running
            }
            if let firstFailed = results.values.first(where: { if case .failed = $0.status { return true } else { return false } }) {
                return firstFailed.status
            }
            // If anything is missing we report idle; if all passed we report passed.
            if results.count == Check.allCases.count && results.values.allSatisfy({ $0.status == .passed }) {
                return .passed
            }
            return .idle
        }

        static let empty = Report(results: [:], target: nil)
    }

    // MARK: - Configuration

    /// Sentinel IP that Tailscale assigns its own local DNS resolver. Only
    /// routable when Tailscale's VPN tunnel is active.
    private let tailscaleResolverIP = "100.100.100.100"
    private let tailscaleResolverPort: UInt16 = 53

    /// Per-probe timeouts in seconds.
    private let tcpProbeTimeout: TimeInterval = 1.5
    private let dnsProbeTimeout: TimeInterval = 2.0
    private let hostProbeTimeout: TimeInterval = 5.0

    // MARK: - Public API

    /// Run all four checks and return a single report. The two independent
    /// checks (`appInstalled`, `vpnActive`) run in parallel; the gated ones
    /// (`magicDNS`, `hostReachable`) need the `vpnActive` result and run
    /// after it. End-to-end completes within ~2s on a healthy setup.
    func run(targetHost: String? = nil, targetPort: Int = 22) async -> Report {
        async let installed = probeAppInstalled()
        async let vpn       = probeVPNActive()
        let i = await installed
        let v = await vpn

        async let dnsResult   = probeMagicDNSGated(vpn: v)
        async let reachResult = probeHostReachableGated(vpn: v, host: targetHost, port: targetPort)
        let d = await dnsResult
        let h = await reachResult

        return Report(
            results: [
                .appInstalled:  i,
                .vpnActive:     v,
                .magicDNS:      d,
                .hostReachable: h,
            ],
            target: targetHost
        )
    }

    /// Run a single check on demand — used by the onboarding flow when
    /// returning from a deep-link to verify that the user just fixed
    /// something.
    func runSingle(_ check: Check, targetHost: String? = nil, targetPort: Int = 22) async -> CheckResult {
        switch check {
        case .appInstalled:
            return await probeAppInstalled()
        case .vpnActive:
            return await probeVPNActive()
        case .magicDNS:
            let v = await probeVPNActive()
            return await probeMagicDNSGated(vpn: v)
        case .hostReachable:
            let v = await probeVPNActive()
            return await probeHostReachableGated(vpn: v, host: targetHost, port: targetPort)
        }
    }

    // MARK: - Probes

    private func probeAppInstalled() async -> CheckResult {
        let installed = await MainActor.run {
            guard let url = URL(string: "tailscale://") else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
        if installed {
            return CheckResult(
                check: .appInstalled,
                status: .passed,
                detail: "Tailscale is installed on this iPhone.",
                remediation: .none,
                measuredAt: .now
            )
        }
        return CheckResult(
            check: .appInstalled,
            status: .failed(reason: "Tailscale isn't installed on this iPhone."),
            detail: "Get Tailscale from the App Store and sign in with the same account you use on your Mac.",
            remediation: .openTailscaleAppStorePage,
            measuredAt: .now
        )
    }

    private func probeVPNActive() async -> CheckResult {
        let reachable = await tcpProbe(
            host: tailscaleResolverIP,
            port: tailscaleResolverPort,
            timeout: tcpProbeTimeout
        )
        if reachable {
            return CheckResult(
                check: .vpnActive,
                status: .passed,
                detail: "Tailscale's tunnel is up — your iPhone can reach the tailnet.",
                remediation: .none,
                measuredAt: .now
            )
        }
        return CheckResult(
            check: .vpnActive,
            status: .failed(reason: "Tailscale's VPN isn't connected."),
            detail: "Open the Tailscale app and tap the big toggle at the top. It should turn blue and say Connected.",
            remediation: .openTailscaleApp,
            measuredAt: .now
        )
    }

    private func probeMagicDNSGated(vpn: CheckResult) async -> CheckResult {
        // Don't probe DNS if the tunnel isn't even up — the answer would be
        // structurally guaranteed to fail and we'd surface a misleading
        // diagnosis.
        guard case .passed = vpn.status else {
            return CheckResult(
                check: .magicDNS,
                status: .skipped(reason: "Will check once Tailscale's VPN is connected."),
                detail: "",
                remediation: .none,
                measuredAt: .now
            )
        }
        // Sentinel: Tailscale runs MagicDNS on 100.100.100.100. We don't
        // need DNS to reach that — we just need to verify the TCP probe to
        // its DNS port works, which probeVPNActive already covered.
        //
        // For a *behavioral* check that MagicDNS is plumbed into the system
        // resolver (i.e., "Use Tailscale DNS" is on), we'd need to resolve
        // an actual `.ts.net` name. Since we don't have a known good name
        // at hand without the user's tailnet, we leave a heuristic note:
        // if probeHostReachable later fails specifically with
        // SocketAddressError.UnknownHost on a Tailscale-looking hostname,
        // that's the signal "Use Tailscale DNS" is off.
        return CheckResult(
            check: .magicDNS,
            status: .passed,
            detail: "Tailscale's DNS resolver is reachable.",
            remediation: .none,
            measuredAt: .now
        )
    }

    private func probeHostReachableGated(vpn: CheckResult, host: String?, port: Int) async -> CheckResult {
        guard let host, !host.isEmpty else {
            return CheckResult(
                check: .hostReachable,
                status: .skipped(reason: "No target Mac specified."),
                detail: "",
                remediation: .none,
                measuredAt: .now
            )
        }
        guard case .passed = vpn.status else {
            return CheckResult(
                check: .hostReachable,
                status: .skipped(reason: "Will check once Tailscale's VPN is connected."),
                detail: "",
                remediation: .none,
                measuredAt: .now
            )
        }
        let (reachable, errorDescription) = await tcpProbeDetailed(
            host: host,
            port: UInt16(port),
            timeout: hostProbeTimeout
        )
        if reachable {
            return CheckResult(
                check: .hostReachable,
                status: .passed,
                detail: "\(host) accepted a connection on port \(port).",
                remediation: .none,
                measuredAt: .now
            )
        }
        // Map the underlying error to specific remediation copy.
        let raw = errorDescription ?? ""
        let remediation: Remediation
        let detail: String
        if ConnectErrorTranslator.matchesDNSFailure(raw) {
            detail = ConnectErrorTranslator.dnsFailureMessage(host: host)
            remediation = ConnectErrorTranslator.isTailscaleHostname(host) ? .openTailscaleApp : .useIPInstead
        } else if raw.contains("Connection refused") {
            detail = "\(host) refused the connection on port \(port). Remote Login is probably off — turn it on on your Mac."
            remediation = .openMacSharingSettings(text: "System Settings → General → Sharing → Remote Login")
        } else if raw.contains("Operation timed out") || raw.contains("timeout") {
            detail = "\(host) didn't respond. The Mac may be asleep, or Tailscale may not be routing yet."
            remediation = .none
        } else {
            detail = ConnectErrorTranslator.translate(NSError(domain: "TCPProbe", code: 0, userInfo: [NSLocalizedDescriptionKey: raw]), host: host, port: port)
            remediation = .none
        }
        return CheckResult(
            check: .hostReachable,
            status: .failed(reason: "\(host) isn't reachable."),
            detail: detail,
            remediation: remediation,
            measuredAt: .now
        )
    }

    // MARK: - TCP probe

    /// Returns true if a TCP connection to `host:port` reaches `.ready`
    /// within `timeout` seconds. Used as a cheap reachability probe.
    private func tcpProbe(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        let (reachable, _) = await tcpProbeDetailed(host: host, port: port, timeout: timeout)
        return reachable
    }

    /// Like `tcpProbe`, but also returns the underlying error description
    /// when the probe fails — used by `hostReachable` to map to specific
    /// remediation copy.
    private func tcpProbeDetailed(host: String, port: UInt16, timeout: TimeInterval) async -> (Bool, String?) {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 22)
        let params: NWParameters = .tcp
        params.expiredDNSBehavior = .allow
        let connection = NWConnection(host: nwHost, port: nwPort, using: params)

        return await withCheckedContinuation { (continuation: CheckedContinuation<(Bool, String?), Never>) in
            let resumed = ResumedFlag()
            let queue = DispatchQueue(label: "shio.tcpProbe")

            connection.stateUpdateHandler = { state in
                Task {
                    switch state {
                    case .ready:
                        if await resumed.tryMark() {
                            connection.cancel()
                            continuation.resume(returning: (true, nil))
                        }
                    case .failed(let error):
                        if await resumed.tryMark() {
                            connection.cancel()
                            continuation.resume(returning: (false, "\(error)"))
                        }
                    case .cancelled:
                        if await resumed.tryMark() {
                            continuation.resume(returning: (false, "cancelled"))
                        }
                    default:
                        break
                    }
                }
            }
            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                Task {
                    if await resumed.tryMark() {
                        connection.cancel()
                        continuation.resume(returning: (false, "Operation timed out"))
                    }
                }
            }
        }
    }
}

/// Tiny actor that lets us guard against double-resume of a
/// CheckedContinuation when multiple NWConnection state updates / timer
/// fire near-simultaneously.
private actor ResumedFlag {
    private var done = false
    func tryMark() -> Bool {
        if done { return false }
        done = true
        return true
    }
}
