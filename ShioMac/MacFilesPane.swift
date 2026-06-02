import SwiftUI
import SwiftData

/// Files on the Mac. The local machine's filesystem is browsable natively —
/// it's *this* machine, so there's no SFTP in the way — shown as "This Mac".
/// Saved remote machines list here too and will browse over SFTP next.
struct MacFilesPane: View {
    @Bindable var model: MacTerminalModel
    @Query(sort: \Host.name) private var machines: [Host]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        LocalDirectoryView(url: FileManager.default.homeDirectoryForCurrentUser,
                                           title: "This Mac", model: model)
                    } label: {
                        MachineFileRow(icon: "laptopcomputer", name: "This Mac",
                                       subtitle: FileManager.default.homeDirectoryForCurrentUser.path)
                    }
                }
                if !machines.isEmpty {
                    Section("Remote") {
                        ForEach(machines) { machine in
                            NavigationLink {
                                RemoteFilesComingSoon(name: machine.name)
                            } label: {
                                MachineFileRow(icon: "desktopcomputer", name: machine.name,
                                               subtitle: "\(machine.username)@\(machine.hostname)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Files")
        }
    }
}

/// A row for a machine in the Files root.
private struct MachineFileRow: View {
    let icon: String
    let name: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Local filesystem browser

/// One directory level on the local Mac. Folders push deeper; files open in
/// their default app. Reveal-in-Finder is on every row's context menu.
private struct LocalDirectoryView: View {
    let url: URL
    let title: String
    @Bindable var model: MacTerminalModel

    @State private var entries: [LocalEntry] = []
    @State private var loadError: String?
    @State private var showHidden = false

    private var filtered: [LocalEntry] {
        let q = model.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.showingSearch {
                SectionSearchField(model: model, placeholder: "Filter \(title)")
            }
            content
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showHidden) { Image(systemName: "eye") }
                    .help("Show hidden files")
            }
        }
        .onAppear(perform: load)
        .onChange(of: showHidden) { _, _ in load() }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
                Text("Can't open this folder").font(.headline)
                Text(loadError).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if entries.isEmpty {
            Text("Empty folder")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filtered) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        LocalDirectoryView(url: entry.url, title: entry.name, model: model)
                    } label: { LocalFileRow(entry: entry) }
                    .contextMenu { revealButton(entry.url) }
                } else {
                    Button { NSWorkspace.shared.open(entry.url) } label: {
                        LocalFileRow(entry: entry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { revealButton(entry.url) }
                }
            }
            .overlay {
                if filtered.isEmpty { Text("No matches").foregroundStyle(.secondary) }
            }
        }
    }

    private func revealButton(_ url: URL) -> some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func load() {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHidden { options.insert(.skipsHiddenFiles) }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: Array(keys), options: options
            )
            entries = urls.map { u in
                let values = try? u.resourceValues(forKeys: keys)
                let isDir = values?.isDirectory ?? false
                return LocalEntry(
                    url: u,
                    name: u.lastPathComponent,
                    isDirectory: isDir,
                    size: isDir ? nil : values?.fileSize.map(UInt64.init)
                )
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }   // folders first
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            loadError = nil
        } catch {
            entries = []
            loadError = error.localizedDescription
        }
    }
}

private struct LocalEntry: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: UInt64?
    var id: String { url.path }
}

private struct LocalFileRow: View {
    let entry: LocalEntry
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 16))
                .foregroundStyle(entry.isDirectory ? .primary : .secondary)
                .frame(width: 22)
            Text(entry.name).font(.body).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let size = entry.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct RemoteFilesComingSoon: View {
    let name: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.full.fill").font(.largeTitle).foregroundStyle(.secondary)
            Text(name).font(.system(.title2, design: .monospaced))
            Text("Browsing this machine over SFTP is coming soon.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(name)
    }
}
