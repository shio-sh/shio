import SwiftUI
import SwiftData

/// iPad-bespoke layout: NavigationSplitView with the host list in the
/// sidebar and the terminal in the detail pane. Designed for landscape
/// + Stage Manager but works in portrait too.
struct IPadRootView: View {

    @Query(sort: \Host.name) private var hosts: [Host]
    @Environment(\.modelContext) private var context

    @State private var selectedHost: Host?
    @State private var isAddingHost = false

    @AppStorage("shio.proMode.enabled", store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var proModeEnabled: Bool = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $isAddingHost) {
            AddHostSheet(proModeEnabled: proModeEnabled)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedHost) {
            // Reinstall banner — only renders when KeyManager.needsReinstall.
            // Wrapping in a Section keeps List happy without showing chrome.
            if KeyManager.needsReinstall {
                Section {
                    KeyReinstallBanner()
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                        .listRowSeparator(.hidden)
                }
            }
            Section("Macs") {
                ForEach(hosts) { host in
                    Label {
                        VStack(alignment: .leading) {
                            Text(host.name)
                                .font(ShioFont.body)
                            Text("\(host.username)@\(host.hostname)")
                                .font(ShioFont.Mono.fingerprint)
                                .foregroundStyle(ShioColor.Text.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "desktopcomputer")
                    }
                    .tag(host)
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(hosts[index]) }
                    try? context.save()
                }
            }

            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("shio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingHost = true
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let host = selectedHost {
            TerminalScene(viewModel: SessionViewModel(
                configuration: host.makeClientConfiguration(),
                persistenceMode: host.persistenceMode
            ))
            .id(host.id)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: ShioSpace.lg) {
            Text("塩")
                .font(ShioFont.kanji(size: 84))
                .foregroundStyle(ShioColor.Text.primary)
            Text("Pick a Mac to begin.")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioColor.Chrome.background)
    }
}
