import SwiftUI
import SwiftData

/// The main host list. iPhone shows it as a sheet over the terminal; iPad
/// will show it in the sidebar (Brick 8).
struct HostListView: View {

    @Query(sort: \Host.lastConnectedAt, order: .reverse) private var hosts: [Host]
    @Environment(\.modelContext) private var context

    @State private var selectedHost: Host?
    @State private var isAddingHost = false

    /// Set by the parent: which kind of "add" sheet to show (Tailscale picker vs Pro Mode).
    @AppStorage("shio.proMode.enabled", store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var proModeEnabled: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if hosts.isEmpty {
                    emptyState
                } else {
                    Section {
                        ForEach(hosts) { host in
                            Button {
                                selectedHost = host
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
            .background(ShioColor.Chrome.background)
            .navigationTitle("shio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingHost = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(ShioColor.Text.primary)
                    }
                }
            }
            .sheet(isPresented: $isAddingHost) {
                AddHostSheet(proModeEnabled: proModeEnabled)
            }
            .fullScreenCover(item: $selectedHost) { host in
                TerminalScene(viewModel: SessionViewModel(
                    configuration: host.makeClientConfiguration(),
                    persistenceMode: host.persistenceMode
                ))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ShioSpace.lg) {
            Spacer().frame(height: 60)
            Text("塩")
                .font(.system(size: 64))
                .foregroundStyle(ShioColor.Text.primary)
            Text("Add your Mac")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)
            Text("Connect to your Mac from your iPhone over Tailscale.")
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
