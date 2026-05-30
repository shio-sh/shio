import SwiftUI
import SwiftData

/// Files tab. Pick a machine, then browse it over SFTP — a Finder-grade file
/// surface on the same connection model as the terminal.
struct FilesView: View {
    @Query(sort: \Host.name) private var hosts: [Host]

    var body: some View {
        NavigationStack {
            Group {
                if hosts.isEmpty {
                    emptyState
                } else {
                    List(hosts) { host in
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
            .navigationTitle("Files")
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
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShioColor.Text.tertiary)
        }
        .padding(.vertical, ShioSpace.xs)
    }
}
