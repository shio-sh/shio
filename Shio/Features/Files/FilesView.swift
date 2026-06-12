import SwiftUI
import SwiftData

/// Files tab. Pick a machine, then browse it over SFTP — a Finder-grade file
/// surface on the same connection model as the terminal.
struct FilesView: View {
    private enum Sort { case name, recent }

    @Query(sort: \Host.name) private var hosts: [Host]
    @State private var showingSettings = false
    @State private var sort: Sort = .name

    private var sortedHosts: [Host] {
        switch sort {
        case .name:   return hosts.dedupedByIdentity   // query is already name-sorted
        case .recent: return hosts.dedupedByIdentity.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hosts.isEmpty {
                    emptyState
                } else {
                    List(sortedHosts) { host in
                        NavigationLink {
                            FileBrowserView(host: host)
                        } label: {
                            HostFileRow(host: host)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ShioTheme.background)
            .shioNavTitle("Files")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            Label("Name", systemImage: "textformat").tag(Sort.name)
                            Label("Recently added", systemImage: "clock").tag(Sort.recent)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(ShioTheme.textPrimary)
                    }
                    .accessibilityLabel("Sort machines")
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
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ShioSpace.lg) {
            Image(systemName: "tray.full.fill")
                .font(.largeTitle)
                .foregroundStyle(ShioTheme.textSecondary)
            Text("No machines yet")
                .font(ShioFont.title2)
                .foregroundStyle(ShioTheme.textPrimary)
            Text("Add or pair a machine in the Machines tab, then browse its files here.")
                .font(ShioFont.body)
                .foregroundStyle(ShioTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioTheme.background)
    }
}

private struct HostFileRow: View {
    let host: Host
    var body: some View {
        HStack(spacing: ShioSpace.md) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 18))
                .foregroundStyle(ShioTheme.textSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(ShioFont.bodyEmphasis)
                    .foregroundStyle(ShioTheme.textPrimary)
                Text(host.hostname)
                    .font(ShioFont.Mono.inline)
                    .foregroundStyle(ShioTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            // No manual chevron — the NavigationLink supplies the disclosure
            // indicator; drawing our own produced a double ">>".
        }
        .padding(.vertical, ShioSpace.xs)
    }
}
