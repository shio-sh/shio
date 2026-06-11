import SwiftUI
import SwiftData

/// Minimal v1 add-project: pick a host you've connected and point at a repo
/// path on it. Repo auto-discovery and clone-by-URL come next in Phase 2.
struct AddProjectSheet: View {
    /// When set, adds another repo under this project instead of a new project.
    var targetProject: Project?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var hosts: [Host]

    /// Where the project's files come from: an existing path on the machine, or
    /// a git URL Shio clones on the machine on first open.
    private enum Source: String, CaseIterable {
        case path = "On machine"
        case clone = "Clone URL"
    }

    @State private var selectedHost: Host?
    @State private var path: String = ""
    @State private var source: Source = .path
    @State private var gitURL: String = ""

    private var trimmedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        gitURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        guard selectedHost != nil, !trimmedPath.isEmpty else { return false }
        if source == .clone, trimmedURL.isEmpty { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if hosts.isEmpty {
                    Section {
                        Text("Add a machine in the Machines tab first, then come back to add a project on it.")
                            .font(ShioFont.callout)
                            .foregroundStyle(ShioTheme.textSecondary)
                    }
                } else {
                    Section("Machine") {
                        Picker("Host", selection: $selectedHost) {
                            ForEach(hosts) { host in
                                Text(host.name).tag(host as Host?)
                            }
                        }
                    }
                    Section {
                        Picker("Source", selection: $source) {
                            ForEach(Source.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if source == .clone {
                        Section {
                            TextField("https://github.com/you/your-repo.git", text: $gitURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(ShioFont.Mono.inline)
                                .keyboardType(.URL)
                        } header: {
                            Text("Git URL")
                        } footer: {
                            Text("Shio runs git clone on the machine, using its own git auth, the first time you open the project.")
                        }
                    }
                    if source == .clone {
                        Section {
                            TextField("/Users/you/code/your-repo", text: $path)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(ShioFont.Mono.inline)
                        } header: {
                            Text("Clone into")
                        } footer: {
                            Text("Absolute path on the machine to clone into. Shio opens a terminal here once it's cloned.")
                        }
                    } else {
                        Section {
                            NavigationLink {
                                if let host = selectedHost {
                                    DirectoryPickerView(
                                        host: host,
                                        initialPath: trimmedPath.isEmpty ? nil : trimmedPath
                                    ) { picked in
                                        path = picked
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Folder")
                                        .foregroundStyle(ShioTheme.textPrimary)
                                    Spacer()
                                    Text(trimmedPath.isEmpty ? "Choose…" : trimmedPath)
                                        .font(trimmedPath.isEmpty ? ShioFont.body : ShioFont.Mono.inline)
                                        .foregroundStyle(trimmedPath.isEmpty ? ShioTheme.textTertiary : ShioTheme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                            }
                            .disabled(selectedHost == nil)
                        } header: {
                            Text("Repo folder")
                        } footer: {
                            Text("Browse the machine and pick the repo folder. Shio opens a terminal there.")
                        }
                    }
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addProject() }
                        .disabled(!canAdd)
                }
            }
            .onAppear {
                if selectedHost == nil { selectedHost = hosts.first }
            }
        }
    }

    private func addProject() {
        guard let host = selectedHost else { return }
        let leaf = (trimmedPath as NSString).lastPathComponent
        let name = leaf.isEmpty ? trimmedPath : leaf
        let cloneURL = (source == .clone && !trimmedURL.isEmpty) ? trimmedURL : nil
        if let target = targetProject {
            target.addRepo(name: name, path: trimmedPath, host: host, cloneURL: cloneURL, in: context)
            target.lastOpenedAt = .now
        } else {
            Project.create(name: name, path: trimmedPath, host: host, cloneURL: cloneURL, in: context)
        }
        try? context.save()
        dismiss()
    }
}
