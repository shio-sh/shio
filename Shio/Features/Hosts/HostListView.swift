import SwiftUI
import SwiftData
import WidgetKit

/// The main host list. iPhone shows it as a sheet over the terminal; iPad
/// will show it in the sidebar (Brick 8).
struct HostListView: View {

    @Query(sort: \Host.lastConnectedAt, order: .reverse) private var hosts: [Host]
    @Environment(\.modelContext) private var context

    /// One row per machine. The same Mac can arrive as two records — the
    /// stamped self-host plus an older un-stamped pairing/synced copy with
    /// identical params — so collapse by (name, hostname, user), keeping the
    /// record that carries a deviceID. (The Mac also merges these at the source;
    /// this keeps the list correct immediately, before that delete syncs in.)
    private var dedupedHosts: [Host] { hosts.dedupedByIdentity }

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
                if hosts.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(dedupedHosts) { host in
                            Button {
                                sessionStore.openOrCreate(host: host)
                                showingTerminal = true
                            } label: {
                                HostRow(host: host)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(ShioTheme.background)
                            .listRowSeparatorTint(ShioTheme.line)
                            // "Remove" (not "Delete") — drops it from Shio
                            // only; the machine itself is untouched.
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { remove(host) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .tint(ShioTheme.danger)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await SyncRefresh.run(context) }
                }
            }
            .background(ShioTheme.background)
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
                            .foregroundStyle(ShioTheme.textPrimary)
                    }
                    .accessibilityLabel("Add a machine")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(ShioTheme.textPrimary)
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
            Text("塩")
                .font(ShioFont.kanji(size: 64))
                .foregroundStyle(ShioTheme.textTertiary)
            Text("Add a machine")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("Reach your Mac — or any SSH server — from your iPhone over Tailscale.")
                .font(ShioFont.callout)
                .foregroundStyle(ShioTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            ShioButton("Get started", .primary, icon: "plus") { isAddingHost = true }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Remove a machine from Shio (the machine itself is left alone).
    private func remove(_ host: Host) {
        // Drop the TOFU pin too — "remove the host and re-add it" is the
        // documented recovery for a changed host key, so removal has to
        // actually clear the pin. Same for the widget's tap targets.
        ShioKnownHosts.forget("\(host.hostname):\(host.port)")
        WidgetSharedState.remove(ids: [host.deviceID, "\(host.persistentModelID)"].compactMap { $0 })
        WidgetCenter.shared.reloadAllTimelines()
        ModelCascade.delete(host: host, context: context)
        try? context.save()
    }
}

private struct HostRow: View {
    let host: Host

    /// No live probe yet — a machine not reached in 3 days reads as asleep.
    private var reachable: Bool {
        guard let last = host.lastConnectedAt else { return false }
        return last.timeIntervalSinceNow > -3 * 24 * 3600
    }

    var body: some View {
        HStack(spacing: ShioSpace.md) {
            ShioStatusDot(status: reachable ? .success : .neutral, filled: reachable)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ShioTheme.textPrimary)
                Text("\(host.username)@\(host.hostname) · \(host.kind.rawValue)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShioTheme.textTertiary)
        }
        .padding(.vertical, ShioSpace.xs)
    }
}
