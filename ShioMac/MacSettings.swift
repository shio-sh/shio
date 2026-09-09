import SwiftUI

/// User preferences for the Mac terminal, persisted in UserDefaults. Read from
/// non-view code (LibGhosttyBridge config, GhosttyMacSurface, MacLocalLaunch)
/// via the static accessors; the Settings UI binds the same keys with @AppStorage.
enum MacSettings {
    static let fontSizeKey = "shio.mac.fontSize"
    static let cursorStyleKey = "shio.mac.cursorStyle"   // block | bar | underline
    static let themeKey = "shio.mac.theme"               // ghostty theme name ("" = default)
    static let shellKey = "shio.mac.defaultShell"

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
    @AppStorage(TmuxControlSession.enabledKey, store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var controlMode: Bool = false
    @AppStorage(PowerKeeper.enabledKey) private var keepAwake: Bool = true
    @AppStorage(PowerKeeper.batteryKey) private var keepAwakeOnBattery: Bool = false

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
                Toggle(isOn: $controlMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("tmux control mode")
                        Text("Let tmux describe the session instead of drawing it. "
                             + "Groundwork for layout that follows you between devices.")
                            .font(.system(size: 11))
                            .foregroundStyle(ShioTheme.textTertiary)
                    }
                }
                    .font(.system(.body, design: .monospaced))
            }
            Section("Power") {
                Toggle("Keep this Mac awake while a device is attached over SSH", isOn: $keepAwake)
                Text("Holds off system sleep only while a device is attached over SSH — released the moment it disconnects. The display still sleeps.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Also on battery", isOn: $keepAwakeOnBattery)
                    .disabled(!keepAwake)
                Text("Off = only while plugged in. A closed lid on battery sleeps regardless — macOS doesn't allow holding clamshell sleep.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: keepAwake) { _, _ in PowerKeeper.shared.reevaluate() }
            .onChange(of: keepAwakeOnBattery) { _, _ in PowerKeeper.shared.reevaluate() }
            Section("Remote control") {
                Text("Mirror: every device that connects sees the live terminal and shares control.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("Changes apply to new terminals. (Per-key remapping is coming — for now use the Terminal and Tabs menus to see shortcuts.)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
    }
}
