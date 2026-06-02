import SwiftUI
import SwiftData

/// Files on the Mac. The local machine's filesystem is browsable natively —
/// it's *this* machine, so there's no SFTP in the way — shown as "This Mac".
/// Saved remote machines list here too and will browse over SFTP next.
struct MacFilesPane: View {
    @Bindable var model: MacTerminalModel
    @Query(sort: \Host.name) private var machines: [Host]

    @State private var spotlight = FileSpotlightSearcher()
    @State private var remote = CrossMachineFileSearcher()

    private var query: String { model.searchQuery.trimmingCharacters(in: .whitespaces) }
    private var searching: Bool { model.showingSearch && !query.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.showingSearch {
                    SectionSearchField(model: model,
                                       placeholder: "Search files across all machines (⏎ to include remote)",
                                       onSubmit: runRemoteSearch)
                }
                if searching {
                    searchResults
                } else {
                    machineList
                }
            }
            .navigationTitle("Files")
        }
        .onChange(of: model.searchQuery) { _, q in spotlight.search(q) }
        .onChange(of: model.showingSearch) { _, on in if !on { spotlight.stop(); remote.cancel() } }
    }

    // The browse home: This Mac + saved machines.
    private var machineList: some View {
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
            let remote = machines.filter { !MacSelfHost.isThisMac($0) }
            if !remote.isEmpty {
                Section("Remote") {
                    ForEach(remote) { machine in
                        NavigationLink {
                            RemoteFilesBrowser(host: machine, model: model)
                        } label: {
                            MachineFileRow(icon: "desktopcomputer", name: machine.name,
                                           subtitle: "\(machine.username)@\(machine.hostname)")
                        }
                    }
                }
            }
        }
    }

    // Cross-machine results: This Mac (Spotlight, live) + each machine (find, on ⏎).
    private var searchResults: some View {
        List {
            Section("This Mac") {
                if spotlight.results.isEmpty {
                    Text("No matches").foregroundStyle(.secondary)
                } else {
                    ForEach(spotlight.results) { hit in
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hit.path)])
                        } label: { hitRow(hit) }
                        .buttonStyle(.plain)
                    }
                }
            }
            ForEach(remote.groups) { group in
                Section(group.name) {
                    switch group.state {
                    case .searching:
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Searching…").foregroundStyle(.secondary) }
                    case .failed(let message):
                        Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    case .results(let hits):
                        if hits.isEmpty {
                            Text("No matches").foregroundStyle(.secondary)
                        } else {
                            ForEach(hits) { hitRow($0) }
                        }
                    }
                }
            }
            if remote.groups.isEmpty && !machines.isEmpty {
                Text("Press ⏎ to also search your \(machines.count) machine\(machines.count == 1 ? "" : "s").")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func hitRow(_ hit: FileHit) -> some View {
        HStack(spacing: 10) {
            Image(systemName: hit.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.name).font(.body).lineLimit(1)
                Text(hit.path).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 1)
    }

    private func runRemoteSearch() {
        let targets = machines.map { (name: $0.name, config: $0.makeClientConfiguration()) }
        remote.search(query, targets: targets)
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

/// Browse a remote machine's files over SFTP (reusing the shared FilesViewModel,
/// which owns its own SSH+SFTP connection). Navigate in place (open dirs, go up);
/// ⌘F filters the current directory; tap a file to download it and open locally.
private struct RemoteFilesBrowser: View {
    let model: MacTerminalModel
    let host: Host
    @State private var vm: FilesViewModel
    @State private var busy = false

    init(host: Host, model: MacTerminalModel) {
        self.host = host
        self.model = model
        _vm = State(initialValue: FilesViewModel(host: host))
    }

    private var filtered: [SFTPFile] {
        let q = model.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return vm.entries }
        return vm.entries.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.showingSearch {
                SectionSearchField(model: model, placeholder: "Filter \(host.name)")
            }
            content
        }
        .navigationTitle(host.name)
        .toolbar {
            ToolbarItem {
                Button { Task { await vm.goUp() } } label: { Image(systemName: "chevron.up") }
                    .help("Up a directory")
                    .disabled(vm.path == "/" || vm.state != .browsing)
            }
        }
        .task { if vm.entries.isEmpty { await vm.start() } }
        .onDisappear { Task { await vm.stop() } }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .connecting:
            VStack(spacing: 8) { ProgressView(); Text("Connecting to \(host.name)…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text("Couldn't open files").font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.start() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        case .browsing:
            List(filtered) { file in
                if file.isDirectory {
                    Button { Task { await vm.open(file) } } label: {
                        SFTPRow(file: file).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else {
                    Button { Task { await openRemoteFile(file) } } label: {
                        SFTPRow(file: file).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(busy)
                }
            }
            .overlay { if filtered.isEmpty { Text("Empty folder").foregroundStyle(.secondary) } }
        }
    }

    /// Download a remote file to a temp dir and open it in its default app.
    private func openRemoteFile(_ file: SFTPFile) async {
        busy = true
        defer { busy = false }
        guard let data = try? await vm.read(file) else { return }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        try? data.write(to: dest)
        NSWorkspace.shared.open(dest)
    }
}

private struct SFTPRow: View {
    let file: SFTPFile
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 16))
                .foregroundStyle(file.isDirectory ? .primary : .secondary)
                .frame(width: 22)
            Text(file.name).font(.body).lineLimit(1).truncationMode(.middle)
            Spacer()
            if !file.isDirectory, let size = file.attributes.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}
