import SwiftUI
import Network
import Darwin
import CoreImage
import AppKit

/// Hosts a one-shot QR pairing handshake on the Mac (the fallback path when
/// devices aren't on the same Apple ID — CloudKit auto-pairing is primary).
///
/// Flow (WhatsApp-Web style, roles fixed by the camera): the Mac SHOWS a QR
/// encoding a `PairingPayload` with a local `endpoint`; the iPhone scans it,
/// generates its SSH key, and POSTs the public key to that endpoint with the
/// one-time token. We validate the token and append the key to
/// `~/.ssh/authorized_keys`, after which the phone can SSH in with its key.
@MainActor
@Observable
final class MacPairingHost {
    enum State: Equatable {
        case starting
        case waiting          // QR shown, listening for the phone
        case paired(String)   // device public-key comment / success
        case failed(String)
    }

    private(set) var state: State = .starting
    private(set) var payload: PairingPayload?
    /// The `shio://pair?d=…` string encoded into the QR.
    private(set) var qrString: String?

    private var listener: NWListener?
    private let token = UUID().uuidString
    private let port: UInt16 = 8730

    func start() {
        state = .starting
        guard let address = Self.reachableIPv4() else {
            state = .failed("Couldn't find a reachable network address for this Mac. Connect to Wi-Fi or Tailscale and try again.")
            return
        }
        let endpoint = "http://\(address):\(port)/pair"
        var p = PairingPayload(
            name: Self.computerName,
            host: address,
            port: 22,
            user: NSUserName()
        )
        p.endpoint = endpoint
        p.token = token
        payload = p
        qrString = Self.deepLink(for: p)

        do {
            try startListener()
            state = .waiting
        } catch {
            state = .failed("Couldn't open the pairing port \(port): \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Listener

    private func startListener() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            // NW callbacks run on the .main queue → safe to assume the main actor.
            MainActor.assumeIsolated { self?.receive(on: conn, buffer: Data()) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    /// Accumulate the request until we have the full body (per Content-Length),
    /// then handle it. Minimal HTTP/1.1 — the phone sends one small POST.
    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }

                if let (headersEnd, contentLength) = Self.parseHeaders(buffer) {
                    let have = buffer.count - headersEnd
                    if have >= contentLength {
                        let body = buffer.subdata(in: headersEnd..<(headersEnd + contentLength))
                        self.handleBody(body, on: conn)
                        return
                    }
                }
                if error != nil || isComplete { conn.cancel(); return }
                self.receive(on: conn, buffer: buffer)
            }
        }
    }

    private func handleBody(_ body: Data, on conn: NWConnection) {
        struct Req: Decodable { let publicKey: String; let token: String }
        func reply(_ status: String, _ json: String) {
            let resp = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\nConnection: close\r\n\r\n\(json)"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
        guard let req = try? JSONDecoder().decode(Req.self, from: body) else {
            reply("400 Bad Request", #"{"ok":false,"error":"bad request"}"#); return
        }
        guard req.token == token else {
            reply("403 Forbidden", #"{"ok":false,"error":"bad token"}"#); return
        }
        do {
            try Self.authorize(publicKey: req.publicKey)
            reply("200 OK", #"{"ok":true}"#)
            state = .paired(Self.comment(of: req.publicKey))
            stop()   // one-shot
        } catch {
            reply("500 Internal Server Error", #"{"ok":false}"#)
            state = .failed("Couldn't authorize the key: \(error.localizedDescription)")
        }
    }

    // MARK: authorized_keys

    /// Append the phone's public key to ~/.ssh/authorized_keys (idempotent),
    /// creating ~/.ssh (700) and the file (600) with correct perms.
    private static func authorize(publicKey: String) throws {
        let fm = FileManager.default
        let ssh = fm.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
        if !fm.fileExists(atPath: ssh.path) {
            try fm.createDirectory(at: ssh, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
        let file = ssh.appendingPathComponent("authorized_keys")
        let line = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if !existing.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == line }) {
            if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
            existing += line + "\n"
            try existing.write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    private static func comment(of publicKey: String) -> String {
        publicKey.split(separator: " ").dropFirst(2).first.map(String.init) ?? "iPhone"
    }

    // MARK: Helpers

    private static func deepLink(for payload: PairingPayload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "shio://pair?d=\(b64)"
    }

    private static var computerName: String {
        // NB: our SwiftData `Host` shadows Foundation.Host here, so use ProcessInfo.
        ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
    }

    /// Parse HTTP headers; return (offset of body start, Content-Length).
    private static func parseHeaders(_ buffer: Data) -> (Int, Int)? {
        let sep = Data("\r\n\r\n".utf8)
        guard let range = buffer.range(of: sep) else { return nil }
        let headerData = buffer.subdata(in: 0..<range.lowerBound)
        let headers = String(decoding: headerData, as: UTF8.self)
        var length = 0
        for line in headers.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return (range.upperBound, length)
    }

    /// Best-effort reachable IPv4: prefer a Tailscale address (100.64/10),
    /// else the first private LAN address.
    private static func reachableIPv4() -> String? {
        var addrs: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.isEmpty && ip != "127.0.0.1" { addrs.append(ip) }
            }
        }
        return addrs.first(where: { $0.hasPrefix("100.") })   // Tailscale CGNAT range
            ?? addrs.first(where: { $0.hasPrefix("192.168.") || $0.hasPrefix("10.") || $0.hasPrefix("172.") })
            ?? addrs.first
    }
}

// MARK: - Pairing sheet

/// Shows the pairing QR and live status. The Mac displays; the iPhone scans.
struct MacPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host = MacPairingHost()

    var body: some View {
        VStack(spacing: 16) {
            Text("Pair your iPhone")
                .font(.system(.title2, design: .monospaced).weight(.semibold))

            switch host.state {
            case .starting:
                ProgressView().frame(width: 220, height: 220)
            case .waiting:
                qr
                VStack(spacing: 4) {
                    Text("Open Shio on your iPhone → Machines → Pair, and scan this.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let p = host.payload {
                        Text("\(p.user)@\(p.host)")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
                Label("Needs Remote Login on (System Settings → General → Sharing).",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            case .paired(let who):
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
                    Text("Paired \(who)").font(.title3)
                    Text("Your iPhone can now reach this Mac.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(width: 220, height: 220)
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                    Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { host.start() }
                }
                .frame(width: 220)
            }

            HStack {
                Spacer()
                Button(host.state.isPaired ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { host.start() }
        .onDisappear { host.stop() }
    }

    @ViewBuilder
    private var qr: some View {
        if let string = host.qrString, let image = Self.qrImage(from: string) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 220, height: 220)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Color.secondary.opacity(0.1).frame(width: 220, height: 220)
        }
    }

    private static func qrImage(from string: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

extension MacPairingHost.State {
    var isPaired: Bool { if case .paired = self { return true } else { return false } }
}
