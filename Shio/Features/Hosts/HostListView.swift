import SwiftUI
import SwiftData

/// The main host list. iPhone shows it as a sheet over the terminal; iPad
/// will show it in the sidebar (Brick 8).
struct HostListView: View {

    @Query(sort: \Host.lastConnectedAt, order: .reverse) private var hosts: [Host]
    @Environment(\.modelContext) private var context

    @State private var isAddingHost = false
    @State private var isPairing = false
    @State private var showingTerminal = false
    @State private var showingSettings = false
    private let sessionStore = SessionStore.shared

    /// Set by the parent: which kind of "add" sheet to show (Tailscale picker vs Pro Mode).
    @AppStorage("shio.proMode.enabled", store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var proModeEnabled: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                KeyReinstallBanner()
                List {
                    if hosts.isEmpty {
                        emptyState
                    } else {
                        Section {
                            ForEach(hosts) { host in
                                Button {
                                    sessionStore.openOrCreate(host: host)
                                    showingTerminal = true
                                } label: {
                                    HostRow(host: host)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteHosts)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(ShioColor.Chrome.background)
            .shioNavTitle("Machines")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isPairing = true
                        } label: {
                            Label("Pair with QR", systemImage: "qrcode.viewfinder")
                        }
                        Button {
                            isAddingHost = true
                        } label: {
                            Label("Add manually", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(ShioColor.Text.primary)
                    }
                    .accessibilityLabel("Add a machine")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(ShioColor.Text.primary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isAddingHost) {
                AddHostSheet(proModeEnabled: proModeEnabled)
            }
            .sheet(isPresented: $isPairing) {
                PairingView()
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
            .fullScreenCover(isPresented: $showingTerminal) {
                TerminalScene()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ShioSpace.lg) {
            Spacer().frame(height: 60)
            Text("塩")
                .font(ShioFont.kanji(size: 64))
                .foregroundStyle(ShioColor.Text.primary)
            Text("Add a machine")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)
            Text("Reach your Mac — or any SSH server — from your iPhone over Tailscale.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioColor.Text.secondary)
                .multilineTextAlignment(.center)
            ShioButton("Get started") {
                isAddingHost = true
            }
            .padding(.horizontal, ShioPadding.screenHorizontalIPhone)
            Spacer()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func deleteHosts(at offsets: IndexSet) {
        for index in offsets {
            context.delete(hosts[index])
        }
        try? context.save()
    }
}

private struct HostRow: View {
    let host: Host

    var body: some View {
        HStack(spacing: ShioSpace.md) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 18))
                .foregroundStyle(ShioColor.Text.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(ShioFont.bodyEmphasis)
                    .foregroundStyle(ShioColor.Text.primary)
                Text("\(host.username)@\(host.hostname)")
                    .font(ShioFont.Mono.inline)
                    .foregroundStyle(ShioColor.Text.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShioColor.Text.tertiary)
        }
        .padding(.vertical, ShioSpace.xs)
    }
}
