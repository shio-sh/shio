import SwiftUI

/// User preferences for the Mac terminal, persisted in UserDefaults. Read from
/// non-view code (LibGhosttyBridge config, GhosttyMacSurface, MacLocalLaunch)
/// via the static accessors; the Settings UI binds the same keys with @AppStorage.
enum MacSettings {
    static let fontSizeKey = "shio.mac.fontSize"
    static let cursorStyleKey = "shio.mac.cursorStyle"   // block | bar | underline
    static let themeKey = "shio.mac.theme"               // ghostty theme name ("" = default)
    static let shellKey = "shio.mac.defaultShell"
    static let menubarWatcherKey = "shio.mac.menubarWatcher"

    static var fontSize: Double {
        let v = UserDefaults.standard.double(forKey: fontSizeKey)
        return v == 0 ? 13 : v
    }
    static var cursorStyle: String {
        UserDefaults.standard.string(forKey: cursorStyleKey) ?? "block"
    }
    static var theme: String {
        UserDefaults.standard.string(forKey: themeKey) ?? ""
    }
    static var defaultShell: String {
        let s = UserDefaults.standard.string(forKey: shellKey) ?? ""
        return s.isEmpty ? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") : s
    }
}

/// The Settings window (⌘,). Font/theme/cursor/shell apply to new terminals;
/// existing tabs keep their look (ghostty config is per-surface at creation).
struct MacSettingsView: View {
    @AppStorage(MacSettings.fontSizeKey) private var fontSize: Double = 13
    @AppStorage(MacSettings.cursorStyleKey) private var cursorStyle: String = "block"
    @AppStorage(MacSettings.themeKey) private var theme: String = ""
    @AppStorage(MacSettings.shellKey) private var shell: String = ""
    @AppStorage(TmuxResume.takeoverKey, store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var takeover: Bool = false
    @AppStorage(MacSettings.menubarWatcherKey) private var menubarWatcher: Bool = false
    @AppStorage(SkillMaterializer.syncEnabledKey) private var skillSync: Bool = true
    @AppStorage(PowerKeeper.enabledKey) private var keepAwake: Bool = true
    @AppStorage(PowerKeeper.batteryKey) private var keepAwakeOnBattery: Bool = false
    @State private var showingSkills = false
    @State private var pinging = false
    @State private var pingResult: String?

    var body: some View {
        Form {
            Section("Terminal") {
                Stepper(value: $fontSize, in: 8...32, step: 1) {
                    Text("Font size: \(Int(fontSize)) pt")
                }
                Picker("Cursor", selection: $cursorStyle) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                }
                TextField("Theme", text: $theme, prompt: Text("ghostty theme name (blank = default)"))
                TextField("Default shell", text: $shell, prompt: Text(ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"))
                    .font(.system(.body, design: .monospaced))
            }
            Section("Power") {
                Toggle("Keep this Mac awake while agents run", isOn: $keepAwake)
                Text("Holds off system sleep only while an agent is working or waiting, or a device is attached over SSH — released the moment they finish. The display still sleeps; sleep would freeze the agent and silence the needs-you push.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Also on battery", isOn: $keepAwakeOnBattery)
                    .disabled(!keepAwake)
                Text("Off = only while plugged in. A closed lid on battery sleeps regardless — macOS doesn't allow holding clamshell sleep.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: keepAwake) { _, _ in PowerKeeper.shared.reevaluate() }
            .onChange(of: keepAwakeOnBattery) { _, _ in PowerKeeper.shared.reevaluate() }
            Section("Remote control") {
                Toggle("Take over on connect", isOn: $takeover)
                Text("Mirror (default): every device sees the live terminal and shares control. Take over: connecting detaches the others so you have sole control.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Keep watching in the menu bar", isOn: $menubarWatcher)
                Text("Stay in the menu bar when the window is closed, so Shio still pushes your phone when an agent needs you. Off = Shio quits with its last window.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    Task { await pingPhone() }
                } label: {
                    HStack {
                        Text("Send test push to your iPhone")
                        if pinging { Spacer(); ProgressView().controlSize(.small) }
                    }
                }
                .disabled(pinging)
                if let pingResult {
                    Text(pingResult).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Writes a Signal through your own iCloud — the exact path a blocked agent uses. The banner lands on your iPhone (works locked), usually within a minute. It can never appear on this Mac: CloudKit doesn't push back to the device that wrote the record.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Skills") {
                Button("Open Skills library…") { showingSkills = true }
                Text("Your universal, vendor-neutral agent rules — global ∪ per-project.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Sync skills to your coding agents", isOn: $skillSync)
                Text("Writes your skills into the folders Claude Code (~/.claude), Cursor, and Codex read, so they're picked up automatically. macOS asks permission the first time (\"data from other apps\"). Off = Shio never touches those folders.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("Changes apply to new terminals. (Per-key remapping is coming — for now use the Terminal and Tabs menus to see shortcuts.)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
        .sheet(isPresented: $showingSkills) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { showingSkills = false }.keyboardShortcut(.defaultAction)
                }
                .padding(12)
                SkillsLibraryView()
            }
            .frame(width: 560, height: 460)
        }
    }

    /// The REAL end-to-end away-push test: this Mac writes a Signal (the exact
    /// record a blocked agent produces) and the iPhone's subscription turns it
    /// into a banner. Cross-device, so it isn't suppressed the way a phone's
    /// own test Signal is.
    private func pingPhone() async {
        pinging = true
        defer { pinging = false }
        do {
            try await CloudKitSignalService.shared.sendTestSignal(
                hostId: MacSelfHost.deviceID,
                sessionId: "shio-test",
                title: "Test from your Mac",
                body: "Away-push works end to end. 塩"
            )
            pingResult = "Signal written ✓ — your iPhone should show the banner within ~10–60s. Lock it to see the Approve/Deny buttons."
        } catch {
            pingResult = "Couldn't write the Signal: \(error.localizedDescription)"
        }
    }
}
