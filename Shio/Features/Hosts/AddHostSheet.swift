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
            .background(ShioColor.Chrome.background)
            .navigationTitle("Add a Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ShioColor.Text.primary)
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

    /// True until the user types in displayName themselves. When true, we
    /// auto-fill displayName from the leading segment of hostname.
    @State private var displayNameAutoFilled: Bool = true

    var body: some View {
        Form {
            Section {
                Text("Enter your Mac's Tailscale name (MagicDNS) so Shio can reach it.")
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioColor.Text.secondary)
            }
            Section("Your Mac") {
                TextField("e.g. studio.tail-scale.ts.net", text: $hostname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(ShioFont.Mono.inline)
                    .onChange(of: hostname) { _, newValue in
                        if displayNameAutoFilled {
                            displayName = inferDisplayName(from: newValue)
                        }
                    }
                TextField("Username (the macOS account name on this Mac)", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Display name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .onChange(of: displayName) { _, _ in
                        // Once the user edits it, stop auto-filling.
                        displayNameAutoFilled = false
                    }
            }
            Section {
                ShioButton("Save") {
                    save()
                }
                .disabled(hostname.isEmpty || username.isEmpty)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// "studio.tail-scale.ts.net" → "Studio". A reasonable first guess that
    /// the user can override.
    private func inferDisplayName(from hostname: String) -> String {
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
                    .foregroundStyle(ShioColor.Text.tertiary)
            }
            Section("Host") {
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
                Picker("Persistence", selection: $persistenceMode) {
                    Text("Tmux auto-resume").tag(Host.PersistenceMode.tmuxAutoResume)
                    Text("Mosh").tag(Host.PersistenceMode.mosh)
                    Text("None").tag(Host.PersistenceMode.plain)
                }
            }
            Section {
                ShioButton("Save") {
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
