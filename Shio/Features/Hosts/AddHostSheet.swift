import SwiftUI
import SwiftData

/// Routes between the Tailscale "Pick your Mac" flow and the Direct-SSH
/// Pro Mode form. The choice is gated by the global `proModeEnabled` flag —
/// Pro Mode users see a segmented control to switch; everyone else only
/// sees the Tailscale flow.
struct AddHostSheet: View {
    let proModeEnabled: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .tailscale

    enum Mode: String, CaseIterable, Hashable {
        case tailscale = "Tailscale"
        case directSSH = "Direct SSH"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if proModeEnabled {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
                    .padding(.vertical, ShioSpace.md)
                }
                Group {
                    switch mode {
                    case .tailscale: TailscaleAddView()
                    case .directSSH: DirectSSHAddView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(ShioTheme.background)
            .navigationTitle("Add a machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ShioTheme.textPrimary)
                }
            }
        }
    }
}

// MARK: - Tailscale flow

private struct TailscaleAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var hostname: String = ""
    @State private var username: String = ""
    @State private var displayName: String = ""
    @State private var useIPInstead: Bool = false
    @State private var helpExpanded: Bool = false

    /// True until the user types in displayName themselves. When true, we
    /// auto-fill displayName from the leading segment of hostname.
    @State private var displayNameAutoFilled: Bool = true

    var body: some View {
        Form {
            Section {
                Text(useIPInstead
                    ? "Enter your Mac's tailnet IP (it starts with 100.)."
                    : "Enter your Mac's Tailscale name (it ends in .ts.net).")
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textSecondary)

                Button {
                    withAnimation(ShioMotion.standard) { helpExpanded.toggle() }
                } label: {
                    HStack(spacing: ShioSpace.xs) {
                        Text("Where do I find this?")
                            .font(ShioFont.callout)
                        Image(systemName: helpExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(ShioTheme.textTertiary)
                }
                .buttonStyle(.plain)

                if helpExpanded {
                    VStack(alignment: .leading, spacing: ShioSpace.xs) {
                        if useIPInstead {
                            Text("Open https://login.tailscale.com/admin/machines on any device. Find your Mac in the list — the column labelled \"Addresses\" shows a `100.x.y.z` IP. That's the one.")
                        } else {
                            Text("On your Mac, click the Tailscale icon in the menu bar. Your Mac is the first entry — its name ends in `.ts.net`. Tap to copy.")
                            Text("Don't see Tailscale in the menu bar? Open it from Applications first.")
                                .font(ShioFont.footnote)
                                .foregroundStyle(ShioTheme.textTertiary)
                        }
                    }
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textSecondary)
                    .padding(.top, ShioSpace.xs)
                }
            }
            Section {
                TextField(
                    useIPInstead ? "100.x.y.z" : "e.g. studio.tail-scale.ts.net",
                    text: $hostname
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(useIPInstead ? .decimalPad : .URL)
                .font(ShioFont.Mono.inline)
                .onChange(of: hostname) { _, newValue in
                    if displayNameAutoFilled {
                        displayName = inferDisplayName(from: newValue)
                    }
                }
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(ShioFont.Mono.inline)
                TextField("Display name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .onChange(of: displayName) { _, _ in
                        displayNameAutoFilled = false
                    }
                Toggle("Use IP instead", isOn: $useIPInstead)
                    .font(ShioFont.callout)
                    .onChange(of: useIPInstead) { _, _ in
                        // Clear hostname so the user starts fresh with the
                        // right keyboard / placeholder for the new mode.
                        hostname = ""
                    }
            } header: {
                Text("Machine details")
            } footer: {
                Text("Username is the account on the machine you're connecting to. On macOS, run `whoami` in Terminal — usually lowercase, no spaces. On Linux servers, the same. Not your Apple ID, not your full name.")
                    .font(ShioFont.footnote)
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            Section {
                ShioButton("Save", .primary, fullWidth: true) {
                    save()
                }
                .disabled(!canSave)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var canSave: Bool {
        guard !hostname.isEmpty, !username.isEmpty else { return false }
        if useIPInstead {
            return isValidIPv4(hostname)
        }
        return true
    }

    /// Minimal IPv4 sanity check — four dot-separated segments, each 0–255.
    /// Not a full validator (that lives in `Network.framework`); just enough
    /// to keep "100" or "foo" out of the field.
    private func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { segment in
            guard let n = Int(segment), (0...255).contains(n) else { return false }
            return true
        }
    }

    /// "studio.tail-scale.ts.net" → "Studio". A reasonable first guess that
    /// the user can override.
    private func inferDisplayName(from hostname: String) -> String {
        // Don't try to humanize a raw IP — leave it for the user.
        if useIPInstead { return hostname }
        let leading = hostname.split(separator: ".").first.map(String.init) ?? ""
        return leading.prefix(1).capitalized + leading.dropFirst()
    }

    private func save() {
        let host = Host(
            name: displayName.isEmpty ? hostname : displayName,
            hostname: hostname,
            username: username,
            kind: .tailscale
        )
        context.insert(host)
        try? context.save()
        dismiss()
    }
}

// MARK: - Direct SSH (Pro) flow

private struct DirectSSHAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var hostname: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var proxyJump: String = ""
    @State private var persistenceMode: Host.PersistenceMode = .tmuxAutoResume

    var body: some View {
        Form {
            Section {
                Text("Pro Mode. Shio doesn't enforce guardrails here — make sure your config is right.")
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            Section("Machine") {
                TextField("Display name", text: $displayName)
                TextField("Hostname or IP", text: $hostname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(ShioFont.Mono.inline)
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Advanced") {
                TextField("ProxyJump (optional)", text: $proxyJump)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(ShioFont.Mono.inline)
                // Mosh (.mosh) is intentionally omitted — it's a model
                // placeholder with no transport yet (SSH-only). Shio's
                // resilience is SSH + tmux + smart auto-reconnect; see
                // SessionViewModel. Re-add when/if a Mosh transport lands.
                Picker("Persistence", selection: $persistenceMode) {
                    Text("Tmux auto-resume").tag(Host.PersistenceMode.tmuxAutoResume)
                    Text("None").tag(Host.PersistenceMode.plain)
                }
            }
            Section {
                ShioButton("Save", .primary, fullWidth: true) {
                    save()
                }
                .disabled(hostname.isEmpty || username.isEmpty)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func save() {
        let host = Host(
            name: displayName.isEmpty ? hostname : displayName,
            hostname: hostname,
            port: Int(port) ?? 22,
            username: username,
            kind: .directSSH,
            persistenceMode: persistenceMode
        )
        host.proxyJump = proxyJump.isEmpty ? nil : proxyJump
        context.insert(host)
        try? context.save()
        dismiss()
    }
}
