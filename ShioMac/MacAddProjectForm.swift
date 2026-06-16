import SwiftUI
import SwiftData

/// Add a project — on **This Mac** or any saved **machine**, from an **existing
/// folder** or by **cloning a Git URL**. Saves the `Project` (host / path /
/// cloneURL) and opens it. Remote folders are typed for now (SSH folder
/// browsing comes with the Files SFTP work); local folders use a picker.
struct MacAddProjectForm: View {
    @Bindable var model: MacTerminalModel
    /// When set, adds another repo under this project instead of creating a new one.
    var targetProject: Project?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var machines: [Host]

    private enum Source: String, CaseIterable, Identifiable {
        case folder = "Existing folder"
        case git = "Clone from Git"
        var id: String { rawValue }
    }

    /// nil = This Mac (local); otherwise a saved machine's id.
    @State private var machineID: PersistentIdentifier?
    @State private var source: Source = .folder
    @State private var name = ""
    @State private var location = ""     // folder path, or the clone parent dir
    @State private var gitURL = ""

    private var selectedMachine: Host? { machines.first { $0.id == machineID } }
    private var isLocal: Bool { machineID == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(targetProject == nil ? "Add a project" : "Add a repo to \(targetProject!.name)")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            if targetProject == nil {
                Text("A project is a workspace. Add more repos to it anytime.")
                    .font(.system(size: 12))
                    .foregroundStyle(ShioTheme.textSecondary)
            }
            Form {
                Picker("Machine", selection: $machineID) {
                    Text("This Mac").tag(PersistentIdentifier?.none)
                    ForEach(machines) { machine in
                        Text(machine.name).tag(Optional(machine.id))
                    }
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
                ShioButton("Add & Open", .primary, compact: true) { add() }
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
                TextField("Path on machine", text: $location,
                          prompt: Text("/home/you/repo"))
                    .font(.system(.body, design: .monospaced))
            }
            TextField(targetProject == nil ? "Project name" : "Name", text: $name, prompt: Text(defaultFolderName))
        case .git:
            TextField("Git URL", text: $gitURL,
                      prompt: Text("https://github.com/you/repo.git"))
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
            TextField(targetProject == nil ? "Project name" : "Name", text: $name, prompt: Text(repoName(from: gitURL).isEmpty ? "repo" : repoName(from: gitURL)))
        }
    }

    // MARK: Validation + helpers

    private var canAdd: Bool {
        switch source {
        case .folder: return !location.trimmingCharacters(in: .whitespaces).isEmpty
        case .git:    return !gitURL.trimmingCharacters(in: .whitespaces).isEmpty
                          && !location.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var defaultFolderName: String {
        (location as NSString).lastPathComponent
    }

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
        panel.message = parentOnly
            ? "Pick the folder to clone into."
            : "Pick a repo or folder on this Mac."
        if panel.runModal() == .OK, let url = panel.url {
            location = url.path
        }
    }

    private func add() {
        // "This Mac" → the synced self-Host record, so the project syncs to
        // other devices with a machine they can SSH into (continuity).
        let host = selectedMachine ?? MacSelfHost.ensure(in: context)
        let cleanLocation = location.trimmingCharacters(in: .whitespaces)

        let typed = name.trimmingCharacters(in: .whitespaces)
        // The repo's own name comes from the folder / git URL.
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

        if let target = targetProject {
            // Adding another repo — the Name field is the repo's name.
            let repo = target.addRepo(name: typed.isEmpty ? folderNm : typed,
                                      path: path, host: host, cloneURL: cloneURL, in: context)
            target.lastOpenedAt = .now
            try? context.save()
            model.open(repo: repo)
        } else {
            // New project — the Name field is the WORKSPACE name; the first repo
            // keeps its folder name (project "shio" → repo "shio-app").
            let project = Project.create(name: typed.isEmpty ? folderNm : typed, repoName: folderNm,
                                         path: path, host: host, cloneURL: cloneURL, in: context)
            project.lastOpenedAt = .now
            try? context.save()
            model.open(project: project)
        }
        dismiss()
    }
}
