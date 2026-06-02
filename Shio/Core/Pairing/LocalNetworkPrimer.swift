import Network

/// Triggers iOS's "allow access to devices on your local network" permission
/// proactively, via a brief Bonjour browse, when the pairing screen opens.
///
/// Pairing POSTs the phone's SSH key to the Mac's local endpoint (a LAN/Tailscale
/// IP). iOS only shows the Local Network prompt on the *first* local access — by
/// default that's mid-POST, after the scan, so the first pairing attempt races
/// the prompt and fails. Priming here resolves the permission before the camera,
/// so the POST succeeds first try.
@MainActor
final class LocalNetworkPrimer {
    private var browser: NWBrowser?

    func prime() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_shio._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
