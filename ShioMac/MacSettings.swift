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
    @AppStorage(TmuxResume.takeoverKey, store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var takeover: Bool = false
    @State private var showingSkills = false

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
            Section("Remote control") {
                Toggle("Take over on connect", isOn: $takeover)
                Text("Mirror (default): every device sees the live session and shares control. Take over: connecting detaches the others so you have sole control.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Skills") {
                Button("Open Skills library…") { showingSkills = true }
                Text("Your universal, vendor-neutral agent rules — global ∪ per-project.")
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
}
