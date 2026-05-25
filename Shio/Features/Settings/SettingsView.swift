import SwiftUI

/// Settings screen. Minimal by design — anything dangerous lives behind
/// Pro Mode (one-time disclosure).
struct SettingsView: View {

    @AppStorage("shio.proMode.enabled", store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var proModeEnabled: Bool = false

    @State private var showingProModeDisclosure = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Shio", systemImage: "info.circle")
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
                            .foregroundStyle(ShioColor.Text.tertiary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ShioColor.Chrome.background)
            .navigationTitle("Settings")
            .alert("Pro Mode", isPresented: $showingProModeDisclosure) {
                Button("OK") { showingProModeDisclosure = false }
            } message: {
                Text("Pro Mode unlocks raw SSH, ProxyJump, custom ports, and manual key management. Shio can't protect you from misconfigurations in this mode.")
            }
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: ShioSpace.lg) {
            Text("塩")
                .font(.system(size: 96))
                .foregroundStyle(ShioColor.Text.primary)
            Text("shio")
                .font(ShioFont.title1)
                .foregroundStyle(ShioColor.Text.primary)
            Text("Your Mac, in your pocket.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioColor.Text.secondary)
            Spacer()
            Text("v1.0")
                .font(ShioFont.footnote)
                .foregroundStyle(ShioColor.Text.tertiary)
        }
        .padding(.top, ShioSpace.layout)
        .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
        .padding(.bottom, ShioSpace.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioColor.Chrome.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}
