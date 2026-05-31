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
        case .name:   return hosts   // query is already name-sorted
        case .recent: return hosts.sorted { $0.createdAt > $1.createdAt }
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
            .background(ShioColor.Chrome.background)
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
                            .foregroundStyle(ShioColor.Text.primary)
                    }
                    .accessibilityLabel("Sort machines")
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
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: ShioSpace.lg) {
            Image(systemName: "tray.full.fill")
                .font(.largeTitle)
                .foregroundStyle(ShioColor.Text.secondary)
            Text("No machines yet")
                .font(ShioFont.title2)
                .foregroundStyle(ShioColor.Text.primary)
            Text("Add or pair a machine in the Hosts tab, then browse its files here.")
                .font(ShioFont.body)
                .foregroundStyle(ShioColor.Text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShioColor.Chrome.background)
    }
}

private struct HostFileRow: View {
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
                Text(host.hostname)
                    .font(ShioFont.Mono.inline)
                    .foregroundStyle(ShioColor.Text.secondary)
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
