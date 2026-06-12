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

    /// Which machine's files the detail shows — the sidebar drives it.
    enum FilesTarget: Hashable { case thisMac, host(PersistentIdentifier) }
    @State private var selection: FilesTarget = .thisMac

    private var remoteHosts: [Host] { machines.dedupedByIdentity.filter { !MacSelfHost.isThisMac($0) } }

    var body: some View {
        VStack(spacing: 0) {
            MacCanvasHeader(title: "Files") {
            } trailing: {
                MacHeaderIconButton(systemImage: "sidebar.trailing", help: "Inspector (⌘I)",
                                    on: model.inspectorOpen) {
                    model.inspectorOpen.toggle()
                }
            }
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        machineRow(.thisMac, icon: "laptopcomputer", name: "This Mac",
                                   sub: FileManager.default.homeDirectoryForCurrentUser.path)
                        ForEach(remoteHosts) { host in
                            machineRow(.host(host.persistentModelID), icon: "desktopcomputer",
                                       name: host.name, sub: "\(host.username)@\(host.hostname)")
                        }
                    }
                    .padding(8)
                }
                .frame(width: 232)
                .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(ShioTheme.line).frame(width: 1)
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
                            browser
                        }
                    }
                    .background(ShioTheme.background)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ShioTheme.background)
        .onChange(of: model.searchQuery) { _, q in spotlight.search(q) }
        .onChange(of: model.showingSearch) { _, on in if !on { spotlight.stop(); remote.cancel() } }
    }

    /// The selected machine's browser. `.id()` resets navigation/listing
    /// state when the sidebar switches machines.
    @ViewBuilder private var browser: some View {
        switch selection {
        case .thisMac:
            LocalDirectoryView(url: FileManager.default.homeDirectoryForCurrentUser,
                               title: "This Mac", model: model, isRoot: true)
        case .host(let id):
            if let host = machines.first(where: { $0.persistentModelID == id }) {
                RemoteFilesBrowser(host: host, model: model).id(id)
            } else {
                Color.clear.onAppear { selection = .thisMac }
            }
        }
    }

    private func machineRow(_ target: FilesTarget, icon: String, name: String, sub: String) -> some View {
        let isSel = selection == target
        return Button { selection = target } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 12.5))
                        .foregroundStyle(isSel ? ShioTheme.accent : ShioTheme.textPrimary)
                        .lineLimit(1)
                    Text(sub).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ShioTheme.textTertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSel ? ShioTheme.accentBg : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .scrollContentBackground(.hidden)
        .background(ShioTheme.background)
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
        // Spotlight already covers this Mac — SSHing into ourselves would
        // just fail (or hit Remote Login) for no gain.
        let targets = machines
            .filter { !MacSelfHost.isThisMac($0) }
            .map { (name: $0.name, config: $0.makeClientConfiguration()) }
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
    /// The machine-level root has no back; pushed folders do.
    var isRoot: Bool = false

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
            // In-canvas path bar — NEVER window-toolbar items (they render
            // glass artifacts and eat the headers' clicks).
            FilesPathBar(title: title, path: url.path, showsBack: !isRoot) {
                FilesBarButton(systemImage: showHidden ? "eye" : "eye.slash",
                               help: "Show hidden files",
                               on: showHidden) { showHidden.toggle() }
            }
            if model.showingSearch {
                SectionSearchField(model: model, placeholder: "Filter \(title)")
            }
            content
        }
        .background(ShioTheme.background)
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
                Group {
                    if entry.isDirectory {
                        NavigationLink {
                            LocalDirectoryView(url: entry.url, title: entry.name, model: model)
                        } label: { LocalFileRow(entry: entry) }
                    } else {
                        Button { NSWorkspace.shared.open(entry.url) } label: {
                            LocalFileRow(entry: entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .contextMenu { revealButton(entry.url) }
                .listRowBackground(ShioTheme.background)
                .listRowSeparatorTint(ShioTheme.line)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ShioTheme.background)
            .overlay {
                if filtered.isEmpty {
                    Text("No matches").font(.system(size: 12.5)).foregroundStyle(ShioTheme.textTertiary)
                }
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
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .font(.system(size: 12))
                .foregroundStyle(entry.isDirectory ? ShioTheme.textSecondary : ShioTheme.textTertiary)
                .frame(width: 18)
            Text(entry.name)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if let size = entry.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// The browser's quiet sub-bar: optional back, title + mono path, trailing
/// controls. Lives inside the canvas — never the window titlebar.
struct FilesPathBar<Trailing: View>: View {
    var title: String
    var path: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss
    /// NavigationStack-pushed levels get a back chevron (macOS draws none).
    var showsBack: Bool = false

    init(title: String, path: String? = nil, showsBack: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.path = path
        self.showsBack = showsBack
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsBack {
                FilesBarButton(systemImage: "chevron.left", help: "Back") { dismiss() }
            }
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1)
            if let path {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShioTheme.line).frame(height: 1)
        }
    }
}

struct FilesBarButton: View {
    let systemImage: String
    var help: String = ""
    var on: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? ShioTheme.accent
                                 : (hovering ? ShioTheme.textPrimary : ShioTheme.textTertiary))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? ShioTheme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
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
            FilesPathBar(title: host.name, path: vm.path) {
                FilesBarButton(systemImage: "chevron.up", help: "Up a directory") {
                    Task { await vm.goUp() }
                }
                .disabled(vm.path == "/" || vm.state != .browsing)
            }
            if model.showingSearch {
                SectionSearchField(model: model, placeholder: "Filter \(host.name)")
            }
            content
        }
        .background(ShioTheme.background)
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
                Group {
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
                .listRowBackground(ShioTheme.background)
                .listRowSeparatorTint(ShioTheme.line)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ShioTheme.background)
            .overlay {
                if filtered.isEmpty {
                    Text("Empty folder").font(.system(size: 12.5)).foregroundStyle(ShioTheme.textTertiary)
                }
            }
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
            Image(systemName: file.isDirectory ? "folder" : "doc")
                .font(.system(size: 12))
                .foregroundStyle(file.isDirectory ? ShioTheme.textSecondary : ShioTheme.textTertiary)
                .frame(width: 18)
            Text(file.name)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if !file.isDirectory, let size = file.attributes.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
