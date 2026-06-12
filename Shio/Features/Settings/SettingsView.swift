import SwiftUI

/// Settings screen. Minimal by design — anything dangerous lives behind
/// Pro Mode (one-time disclosure).
struct SettingsView: View {

    @AppStorage("shio.proMode.enabled", store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var proModeEnabled: Bool = false

    @AppStorage(AppLock.defaultsKey, store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var appLockEnabled: Bool = false

    @AppStorage(TmuxResume.takeoverKey, store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var takeoverMode: Bool = false

    @AppStorage("shio.key.useEnclave") private var useEnclaveKey: Bool = false

    @State private var showingProModeDisclosure = false
    @State private var testPushResult: String?
    @State private var sendingTestPush = false
    @State private var creatingAction = false

    var body: some View {
        NavigationStack {
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
                        SkillsLibraryView()
                    } label: {
                        Label("Skills", systemImage: "wrench.and.screwdriver.fill")
                    }
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
                    .tint(.green)
                    .onChange(of: appLockEnabled) { _, newValue in
                        print("[shio] appLock toggle → \(newValue)")
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
                    Text("Shio re-authenticates if you leave the app for more than 10 seconds. SSH sessions stay connected while locked.")
                        .font(ShioFont.footnote)
                        .foregroundStyle(ShioTheme.textTertiary)
                }

                Section {
                    Toggle(isOn: $takeoverMode) {
                        Label("Take over on connect", systemImage: "rectangle.on.rectangle.angled")
                    }
                    .tint(.green)
                    Text("Mirror (default): every device sees the live session and shares control. Take over: connecting from a device detaches the others so you have sole control.")
                        .font(ShioFont.footnote)
                        .foregroundStyle(ShioTheme.textTertiary)
                } header: {
                    Text("Remote control")
                }

                if KeyManager.enclaveAvailable() {
                    Section {
                        Toggle(isOn: $useEnclaveKey) {
                            Label("Hardware key (Secure Enclave)", systemImage: "lock.shield")
                        }
                        .tint(.green)
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
                    .tint(.green)
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

                if proModeEnabled {
                    Section {
                        Button {
                            Task { await sendTestPush() }
                        } label: {
                            HStack {
                                Label("Send test notification", systemImage: "bell.badge")
                                Spacer()
                                if sendingTestPush { ProgressView() }
                            }
                        }
                        .disabled(sendingTestPush)

                        Button {
                            Task { await createActionSchema() }
                        } label: {
                            HStack {
                                Label("Create approve channel", systemImage: "checkmark.message")
                                Spacer()
                                if creatingAction { ProgressView() }
                            }
                        }
                        .disabled(creatingAction)
                    } header: {
                        Text("Notifications")
                    } footer: {
                        Text("\"Send test notification\" verifies away-push delivers. \"Create approve channel\" writes one Action record so the CloudKit \"Action\" record type appears in Development — then make it Queryable and deploy it to Production (that's what powers lock-screen approve).")
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
            .alert("Test notification", isPresented: Binding(get: { testPushResult != nil }, set: { if !$0 { testPushResult = nil } })) {
                Button("OK") { testPushResult = nil }
            } message: {
                Text(testPushResult ?? "")
            }
        }
    }

    /// Write one Action record so CloudKit materializes the `Action` record type
    /// in Development — the one-time step that makes it deployable to Production.
    private func createActionSchema() async {
        creatingAction = true
        defer { creatingAction = false }
        await CloudKitSignalService.shared.sendAction(sessionId: "shio-schema-probe", key: "y")
        testPushResult = "Wrote a test Action. In CloudKit Console → Development → Record Types, the “Action” type should now appear. Make it Queryable, then Deploy Schema Changes to Production."
    }

    private func sendTestPush() async {
        sendingTestPush = true
        defer { sendingTestPush = false }
        // REQUEST permission (prompts the first time), then register — not just
        // registerIfAuthorized, which silently skips when status is notDetermined.
        await PushService.shared.requestAuthorizationAndRegister()
        // The APNs token arrives async via the delegate callback, so it may be
        // nil on this first tap right after granting — tap again to confirm.
        let token = PushService.shared.deviceToken
        do {
            try await CloudKitSignalService.shared.sendTestSignal()
            if let token {
                testPushResult = "Signal saved ✓\nPush token: …\(token.suffix(8)) ✓\n\nThe banner can take 10–60s (CloudKit isn't instant). Lock the phone and wait."
            } else {
                testPushResult = "Signal saved ✓, BUT this device has no APNs push token — registerForRemoteNotifications didn't complete. CloudKit has no way to deliver. Likely the Push Notifications capability isn't enabled on the sh.shio.app App ID. Check Xcode's Signing & Capabilities (add Push Notifications) and the log for 'APNs registration failed'."
            }
        } catch {
            testPushResult = "Couldn't send: \(error.localizedDescription)"
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
            Text("Your Mac, in your pocket.")
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
