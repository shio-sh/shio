import SwiftUI

/// Settings screen. Minimal by design — anything dangerous lives behind
/// Pro Mode (one-time disclosure).
struct SettingsView: View {

    @AppStorage("shio.proMode.enabled", store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var proModeEnabled: Bool = false

    @AppStorage(AppLock.defaultsKey, store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var appLockEnabled: Bool = false

    @AppStorage("shio.key.useEnclave") private var useEnclaveKey: Bool = false

    @State private var showingProModeDisclosure = false

    // NB: no NavigationStack here — every call site (Projects, Files,
    // Machines) presents SettingsView inside its own stack; nesting a second
    // one broke push animations and doubled the bar.
    var body: some View {
        Form {
                if let reason = ShioModelContainer.loadFailureReason {
                    Section {
                        VStack(alignment: .leading, spacing: ShioSpace.xs) {
                            Label("Storage issue", systemImage: "exclamationmark.triangle.fill")
                                .font(ShioFont.bodyEmphasis)
                                .foregroundStyle(ShioTheme.warning)
                            Text(reason)
                                .font(ShioFont.callout)
                                .foregroundStyle(ShioTheme.textSecondary)
                        }
                    }
                }
                Section {
                    NavigationLink {
                        PublicKeyView(mode: .settings)
                            .navigationTitle("SSH Key")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("SSH Key", systemImage: "key.fill")
                    }
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnose connection", systemImage: "stethoscope")
                    }
                    NavigationLink {
                        IconPickerView()
                    } label: {
                        Label("App Icon", systemImage: "app.dashed")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Shio", systemImage: "info.circle")
                    }
                }
                Section("Security") {
                    Toggle(isOn: $appLockEnabled) {
                        Label(appLockToggleTitle, systemImage: appLockToggleIcon)
                    }
                    .onChange(of: appLockEnabled) { _, newValue in
                        guard newValue else { return }
                        Task {
                            let ok = await AppLock.authenticate(
                                reason: "Confirm that Shio can lock with \(AppLock.methodLabel)."
                            )
                            await MainActor.run {
                                if !ok { appLockEnabled = false }
                            }
                        }
                    }
                    Text("Shio re-authenticates if you leave the app for more than 10 seconds. SSH connections stay alive while locked.")
                        .font(ShioFont.footnote)
                        .foregroundStyle(ShioTheme.textTertiary)
                }

                if KeyManager.enclaveAvailable() {
                    Section {
                        Toggle(isOn: $useEnclaveKey) {
                            Label("Hardware key (Secure Enclave)", systemImage: "lock.shield")
                        }
                            .onChange(of: useEnclaveKey) { _, on in
                            guard on else { return }
                            Task.detached { try? KeyManager.generateEnclaveIfNeeded() }
                            KeyManager.markReinstallNeeded()
                        }
                        Text("Store this device's SSH key in the Secure Enclave — the private key never leaves the chip and can't be copied off the device. After turning this on, re-install the public key on your Macs from SSH Key above. Off = the standard key.")
                            .font(ShioFont.footnote)
                            .foregroundStyle(ShioTheme.textTertiary)
                    } header: {
                        Text("SSH key")
                    }
                }

                Section("Advanced") {
                    Toggle(isOn: $proModeEnabled) {
                        Label("Pro Mode", systemImage: "wrench.adjustable.fill")
                    }
                    .onChange(of: proModeEnabled) { _, newValue in
                        if newValue {
                            // Only show disclosure once.
                            let key = "shio.proMode.seenDisclosure"
                            let defaults = UserDefaults(suiteName: ShioModelContainer.appGroup)
                            if defaults?.bool(forKey: key) != true {
                                showingProModeDisclosure = true
                                defaults?.set(true, forKey: key)
                            }
                        }
                    }
                    if proModeEnabled {
                        Text("Pro Mode unlocks raw SSH config — custom ports, ProxyJump, manual key management. Shio can't protect you from misconfigurations here.")
                            .font(ShioFont.footnote)
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ShioTheme.background)
            .navigationTitle("Settings")
            .alert("Pro Mode", isPresented: $showingProModeDisclosure) {
                Button("OK") { showingProModeDisclosure = false }
            } message: {
                Text("Pro Mode unlocks raw SSH, ProxyJump, custom ports, and manual key management. Shio can't protect you from misconfigurations in this mode.")
            }
    }

    private var appLockToggleTitle: String {
        switch AppLock.biometryType {
        case .faceID:  return "Require Face ID"
        case .touchID: return "Require Touch ID"
        case .opticID: return "Require Optic ID"
        default:       return "Require device passcode"
        }
    }

    private var appLockToggleIcon: String {
        switch AppLock.biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default:       return "lock.fill"
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: ShioSpace.md) {
            Text("塩")
                .font(ShioFont.kanji(size: 96))
                .foregroundStyle(ShioTheme.textPrimary)
            Text("shio")
                .font(ShioFont.wordmark(size: 32))
                .foregroundStyle(ShioTheme.textPrimary)
            Text("A real terminal for the agent era.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
            Spacer()
            Text("v1.0")
                .font(ShioFont.footnote)
                .foregroundStyle(ShioTheme.textTertiary)
        }
        .padding(.top, ShioSpace.layout)
        .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
        .padding(.bottom, ShioSpace.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioTheme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}
