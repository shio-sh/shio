import SwiftUI
import UserNotifications

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

    @AppStorage(SkillMaterializer.syncEnabledKey) private var skillSync: Bool = true

    @State private var showingProModeDisclosure = false
    @State private var testPushResult: String?
    @State private var sendingTestPush = false
    @State private var creatingAction = false

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
                    Text("Shio re-authenticates if you leave the app for more than 10 seconds. SSH sessions stay connected while locked.")
                        .font(ShioFont.footnote)
                        .foregroundStyle(ShioTheme.textTertiary)
                }

                Section {
                    Toggle(isOn: $takeoverMode) {
                        Label("Take over on connect", systemImage: "rectangle.on.rectangle.angled")
                    }
                    Text("Mirror (default): every device sees the live session and shares control. Take over: connecting from a device detaches the others so you have sole control.")
                        .font(ShioFont.footnote)
                        .foregroundStyle(ShioTheme.textTertiary)
                } header: {
                    Text("Remote control")
                }

                Section {
                    Toggle(isOn: $skillSync) {
                        Label("Sync skills to your agents", systemImage: "wrench.and.screwdriver")
                    }
                    Text("Writes your skills into the folders the agents on your machines read (~/.claude, ~/.cursor, ~/.codex) when you open a project. Off = Shio never touches those folders.")
                        .font(ShioFont.footnote)
                        .foregroundStyle(ShioTheme.textTertiary)
                } header: {
                    Text("Skills")
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
        // Denied is its own diagnosis — without permission there's no banner
        // no matter what else is right, and "capability missing" would lie.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            testPushResult = "Notifications are denied for Shio. Enable them in Settings → Apps → Shio → Notifications, then try again."
            return
        }
        // Server-side subscription check (the local latch can lie across
        // reinstalls / Dev→Prod switches) — repairs it if missing.
        let subscription = await CloudKitSignalService.shared.verifySubscription()
        let subLine: String
        switch subscription {
        case .active:  subLine = "Subscription: active ✓"
        case .created: subLine = "Subscription: was missing — created ✓"
        case .unavailable(let why):
            testPushResult = "CloudKit subscription problem: \(why)"
            return
        }
        // The APNs token arrives via an async delegate callback — give it a
        // moment instead of mis-diagnosing a missing capability on first tap.
        var token = PushService.shared.deviceToken
        for _ in 0..<10 where token == nil {
            try? await Task.sleep(nanoseconds: 300_000_000)
            token = PushService.shared.deviceToken
        }
        guard let token else {
            testPushResult = "\(subLine)\nBUT this device has no APNs push token — registerForRemoteNotifications didn't complete. CloudKit has no way to deliver. Likely the Push Notifications capability isn't enabled on the sh.shio.app App ID. Check Xcode's Signing & Capabilities (add Push Notifications) and the log for 'APNs registration failed'."
            return
        }
        do {
            try await CloudKitSignalService.shared.sendTestSignal()
            // Rehearse the banner locally (same category → the lock-screen
            // Approve/Deny buttons), because the CloudKit push for the Signal
            // we just wrote will NEVER arrive here: Apple doesn't deliver a
            // subscription push to the device that originated the change.
            await scheduleRehearsalBanner()
            testPushResult = "\(subLine)\nSignal saved ✓\nPush token: …\(token.suffix(8)) ✓\n\nThis phone can't receive its own test Signal — CloudKit never pushes back to the device that wrote the record. A local rehearsal banner (same Approve/Deny category) arrives in ~3s; lock the phone to see it there.\n\nThe real end-to-end test is on your Mac: Settings → Remote control → “Send test push to your iPhone”."
        } catch {
            testPushResult = "\(subLine)\nCouldn't write the Signal: \(error.localizedDescription)"
        }
    }

    /// A local stand-in for the away banner: same category, so the lock-screen
    /// Approve / Deny buttons render exactly as the real push would show them.
    private func scheduleRehearsalBanner() async {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code needs you"
        content.body = "Rehearsal banner — this is how an away-push looks. Approve/Deny work from the lock screen."
        content.sound = .default
        content.categoryIdentifier = CloudKitSignalService.needsYouCategory
        content.userInfo = ["sessionId": "shio-test", "hostId": ""]
        let request = UNNotificationRequest(
            identifier: "shio-test-banner",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
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
