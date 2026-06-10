import SwiftUI

/// Settings screen. Minimal by design — anything dangerous lives behind
/// Pro Mode (one-time disclosure).
struct SettingsView: View {

    @AppStorage("shio.proMode.enabled", store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var proModeEnabled: Bool = false

    @AppStorage(AppLock.defaultsKey, store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var appLockEnabled: Bool = false

    @State private var showingProModeDisclosure = false
    @State private var testPushResult: String?
    @State private var sendingTestPush = false

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
                    } header: {
                        Text("Notifications")
                    } footer: {
                        Text("Writes a CloudKit signal and pushes it back to this device — to verify away-push is delivering. Requires the iCloud container to be set up.")
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

    private func sendTestPush() async {
        sendingTestPush = true
        defer { sendingTestPush = false }
        do {
            try await CloudKitSignalService.shared.sendTestSignal()
            testPushResult = "Signal sent. The push should arrive in a few seconds (works on a real device with iCloud signed in)."
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
