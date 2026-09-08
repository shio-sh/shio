import SwiftUI
import SwiftData
import AppKit

/// Create a project on the Mac — a workspace with a logo, context (memory),
/// project-scoped skills, and any number of repos across **This Mac** or saved
/// **machines**, each from an existing folder or a Git URL. Everything is
/// optional except a name. When `targetProject` is set the form collapses to the
/// single repo editor (add a repo to an existing project).
struct MacAddProjectForm: View {
    @Bindable var model: MacTerminalModel
    var targetProject: Project?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var machines: [Host]

    @State private var draft = ProjectDraft()
    @State private var editingRepo = false

    var body: some View {
        if let target = targetProject {
            MacRepoEditor(machines: machines, title: "Add a repo to \(target.name)") { spec in
                let repo = target.addRepo(name: spec.name, path: spec.path,
                                          host: resolveHost(spec.hostID),
                                          cloneURL: spec.cloneURL, in: context)
                target.lastOpenedAt = .now
                try? context.save()
                model.open(repo: repo)
                dismiss()
            }
        } else {
            newProjectForm
        }
    }

    // MARK: New project

    private var newProjectForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                MacLogoWell(name: draft.name, imageData: draft.imageData) { draft.imageData = $0 }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Project name", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                    Text("A workspace for the repos and context below.")
                        .font(.system(size: 12))
                        .foregroundStyle(ShioTheme.textSecondary)
                }
            }

            Form {
                Section {
                    ForEach(draft.repos) { repo in
                        HStack {
                            MacRepoRow(repo: repo)
                            Button { draft.repos.removeAll { $0.id == repo.id } } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ShioTheme.textTertiary)
                        }
                    }
                    Button { editingRepo = true } label: {
                        Label(draft.repos.isEmpty ? "Add a repo…" : "Add another repo…", systemImage: "plus")
                    }
                } header: {
                    Text("Repos")
                } footer: {
                    Text("Across This Mac or any machine — or none for now; add them anytime.")
                        .font(.system(size: 11)).foregroundStyle(ShioTheme.textTertiary)
                }

            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                ShioButton("Create & Open", .primary, compact: true) { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canCreate)
            }
        }
        .padding(20)
        .frame(width: 520)
        .frame(maxHeight: 660)
        .sheet(isPresented: $editingRepo) {
            MacRepoEditor(machines: machines) { draft.repos.append($0) }
        }
    }

    private func resolveHost(_ id: PersistentIdentifier?) -> Host? {
        guard let id else { return MacSelfHost.ensure(in: context) }
        return machines.first { $0.id == id }
    }

    private func create() {
        let project = Project.build(from: draft, resolveHost: resolveHost, in: context)
        model.open(project: project)
        dismiss()
    }
}

// MARK: - One repo in the draft list

private struct MacRepoRow: View {
    let repo: RepoSpec
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: repo.cloneURL != nil ? "arrow.down.circle" : "folder")
                .foregroundStyle(ShioTheme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name).font(.system(size: 13, weight: .medium))
                Text("\(repo.machineLabel) · \(repo.path)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShioTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }
}

// MARK: - Repo editor (machine + folder/git → RepoSpec)

private struct MacRepoEditor: View {
    let machines: [Host]
    var title: String = "Add a repo"
    var onSave: (RepoSpec) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Source: String, CaseIterable, Identifiable {
        case folder = "Existing folder"
        case git = "Clone from Git"
        var id: String { rawValue }
    }

    @State private var machineID: PersistentIdentifier?
    @State private var source: Source = .folder
    @State private var location = ""
    @State private var gitURL = ""

    private var isLocal: Bool { machineID == nil }
    private var machineLabel: String {
        machineID == nil ? "This Mac" : (machines.first { $0.id == machineID }?.name ?? "Machine")
    }

    private var canAdd: Bool {
        switch source {
        case .folder: return !location.trimmingCharacters(in: .whitespaces).isEmpty
        case .git:    return !gitURL.trimmingCharacters(in: .whitespaces).isEmpty
                          && !location.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            Form {
                Picker("Machine", selection: $machineID) {
                    Text("This Mac").tag(PersistentIdentifier?.none)
                    ForEach(machines) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("From", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                sourceFields
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                ShioButton("Add", .primary, compact: true) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private var sourceFields: some View {
        switch source {
        case .folder:
            if isLocal {
                LabeledContent("Folder") {
                    HStack {
                        Text(location.isEmpty ? "Choose a folder…" : location)
                            .foregroundStyle(location.isEmpty ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder(parentOnly: false) }
                    }
                }
            } else {
                TextField("Path on machine", text: $location, prompt: Text("/home/you/repo"))
                    .font(.system(.body, design: .monospaced))
            }
        case .git:
            TextField("Git URL", text: $gitURL, prompt: Text("https://github.com/you/repo.git"))
                .font(.system(.body, design: .monospaced))
                .textContentType(.URL)
            if isLocal {
                LabeledContent("Clone into") {
                    HStack {
                        Text(location.isEmpty ? "Choose a parent folder…" : location)
                            .foregroundStyle(location.isEmpty ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder(parentOnly: true) }
                    }
                }
            } else {
                TextField("Clone into", text: $location, prompt: Text("/home/you"))
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var defaultFolderName: String { (location as NSString).lastPathComponent }

    /// "https://github.com/you/repo.git" / "git@github.com:you/repo.git" → "repo".
    private func repoName(from url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        while s.hasSuffix("/") { s = String(s.dropLast()) }
        return s.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
    }

    private func chooseFolder(parentOnly: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = parentOnly ? "Pick the folder to clone into." : "Pick a repo or folder on this Mac."
        if panel.runModal() == .OK, let url = panel.url { location = url.path }
    }

    private func commit() {
        let cleanLocation = location.trimmingCharacters(in: .whitespaces)
        let folderNm: String
        let path: String
        let cloneURL: String?
        switch source {
        case .folder:
            folderNm = (cleanLocation as NSString).lastPathComponent
            path = cleanLocation
            cloneURL = nil
        case .git:
            folderNm = repoName(from: gitURL)
            path = (cleanLocation as NSString).appendingPathComponent(folderNm)
            cloneURL = gitURL.trimmingCharacters(in: .whitespaces)
        }
        onSave(RepoSpec(name: folderNm.isEmpty ? defaultFolderName : folderNm, path: path,
                        hostID: machineID, cloneURL: cloneURL, machineLabel: machineLabel))
        dismiss()
    }
}
