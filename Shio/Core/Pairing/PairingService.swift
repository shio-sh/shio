import Foundation

/// The phone side of the WhatsApp-Web-style pairing handshake:
///   1. Ensure this device has an SSH key (generate on first run).
///   2. If the scanned payload carries a companion `endpoint`, POST the
///      public key there so the companion authorizes it on the host.
///   3. Return the OpenSSH `authorized_keys` line so the UI can offer a
///      paste-it-yourself fallback when there's no live companion.
///
/// RUNTIME NOTE: the network step talks to the Mac's local pairing
/// listener (`MacPairingHost` in the Shio Mac app). This compiles and runs
/// app-side, but only completes end-to-end against a live listener on the
/// same reachable network — validate on a real device + machine.
enum PairingService {

    enum PairingError: LocalizedError {
        case keyUnavailable(String)
        case submitFailed(String)

        var errorDescription: String? {
            switch self {
            case .keyUnavailable(let s): return "Couldn't prepare this device's SSH key: \(s)"
            case .submitFailed(let s):   return "Pairing handshake failed: \(s)"
            }
        }
    }

    /// Ensure the device key exists and, if the payload carries a companion
    /// endpoint, submit the public key for authorization. Returns the OpenSSH
    /// line (useful for the manual fallback UI). Throws on key or network
    /// failure so the caller can surface it.
    @discardableResult
    static func provisionKey(for payload: PairingPayload) async throws -> String {
        let line: String
        do {
            let key = try KeyManager.generateIfNeeded()
            line = OpenSSHFormatter.authorizedKeysLine(publicKey: key.publicKey)
        } catch {
            throw PairingError.keyUnavailable(error.localizedDescription)
        }

        if let endpoint = payload.endpoint,
           let url = URL(string: endpoint),
           url.scheme?.hasPrefix("http") == true {
            try await submit(line: line, token: payload.token, to: url)
        }
        return line
    }

    /// Build a `Host` from a scanned payload. The caller inserts + saves it
    /// into the SwiftData context (so we don't couple this service to one).
    static func makeHost(from payload: PairingPayload) -> Host {
        let host = Host(
            name: payload.name,
            hostname: payload.host,
            port: payload.port,
            username: payload.user,
            kind: .directSSH
        )
        host.deviceID = payload.deviceID
        return host
    }

    private static func submit(line: String, token: String?, to url: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        let body: [String: String] = ["publicKey": line, "token": token ?? ""]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw PairingError.submitFailed("no response from companion")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw PairingError.submitFailed("companion rejected the key (HTTP \(http.statusCode))")
            }
        } catch let e as PairingError {
            throw e
        } catch {
            throw PairingError.submitFailed(error.localizedDescription)
        }
    }
}
