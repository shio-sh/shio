import SwiftUI
import SwiftData
import WidgetKit

/// The machines list — pushed from the More tab (it relies on the enclosing
/// NavigationStack for its title + toolbar).
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
    private let sessionStore = SessionStore.shared

    /// Set by the parent: which kind of "add" sheet to show (Tailscale picker vs Pro Mode).
    @AppStorage("shio.proMode.enabled", store: UserDefaults(suiteName: ShioModelContainer.appGroup))
    private var proModeEnabled: Bool = false

    /// A machine holds the checkouts that place your repos on it, so removing
    /// one is not the small act the swipe makes it look like.
    @State private var removeTarget: Host?
    @State private var editTarget: Host?

    var body: some View {
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
                            Button(role: .destructive) { removeTarget = host } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .tint(ShioTheme.danger)
                            Button { editTarget = host } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await SyncRefresh.run(context) }
            }
        }
        .background(ShioTheme.background)
        .alert("Couldn't sync", isPresented: Binding(
            get: { SyncRefresh.lastFailure != nil },
            set: { if !$0 { SyncRefresh.clearFailure() } })) {
            Button("OK") { SyncRefresh.clearFailure() }
        } message: {
            Text(SyncRefresh.lastFailure ?? "")
        }
        .sheet(item: $editTarget) { EditHostSheet(host: $0) }
        .confirmationDialog(
            removeTarget.map { "Remove \($0.name) from Shio?" } ?? "Remove machine?",
            isPresented: Binding(get: { removeTarget != nil },
                                 set: { if !$0 { removeTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let h = removeTarget { remove(h) }
                removeTarget = nil
            }
            Button("Cancel", role: .cancel) { removeTarget = nil }
        } message: {
            Text("Shio forgets this machine and where your repos sit on it. The machine itself is untouched, and its files and sessions are unaffected. This syncs to your other devices.")
        }
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
        }
        .sheet(isPresented: $isAddingHost) {
            AddHostSheet(proModeEnabled: proModeEnabled)
        }
        .sheet(isPresented: $isPairing) {
            PairingView()
        }
        .fullScreenCover(isPresented: $showingTerminal) {
            TerminalScene()
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
