import SwiftUI
import SwiftData
import PhotosUI

/// Create a project — a workspace that can hold a logo, context (memory),
/// project-scoped skills, and any number of repos across machines. Everything
/// is optional except a name, so it's still one tap to make an empty project
/// and fill it in later. When `targetProject` is set the sheet collapses to the
/// single repo editor (add a repo to an existing project).
struct AddProjectSheet: View {
    var targetProject: Project?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var hosts: [Host]

    @State private var draft = ProjectDraft()
    @State private var photoItem: PhotosPickerItem?
    @State private var editingRepo = false
    @State private var groundingExpanded = false
    @State private var pairing = false

    var body: some View {
        NavigationStack {
            if let target = targetProject {
                RepoEditor(hosts: hosts, title: "Add a repo") { spec in
                    target.addRepo(name: spec.name, path: spec.path,
                                   host: hosts.first { $0.persistentModelID == spec.hostID },
                                   cloneURL: spec.cloneURL, in: context)
                    target.lastOpenedAt = .now
                    try? context.save()
                    dismiss()
                }
            } else {
                newProjectForm
            }
        }
    }

    // MARK: New project

    private var newProjectForm: some View {
        Form {
            identitySection
            reposSection
            groundingSection
        }
        .navigationTitle("New project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { create() }.disabled(!draft.canCreate)
            }
        }
        .sheet(isPresented: $editingRepo) {
            NavigationStack {
                RepoEditor(hosts: hosts) { draft.repos.append($0) }
            }
        }
        .sheet(isPresented: $pairing) { PairingView() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let encoded = ProjectAvatar.encode(data) {
                    draft.imageData = encoded
                }
            }
        }
    }

    // Read the draft into Sendable locals here (main actor) so the PhotosPicker
    // label closure — which strict concurrency treats as Sendable — captures
    // plain values instead of the main-actor-isolated `draft`.
    private var logoPicker: some View {
        let avatarName = draft.name.isEmpty ? "?" : draft.name
        let avatarData = draft.imageData
        return PhotosPicker(selection: $photoItem, matching: .images) {
            ProjectAvatar(name: avatarName, imageData: avatarData, size: 52)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 17))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(ShioTheme.textSecondary, ShioTheme.surface)
                        .offset(x: 4, y: 4)
                }
        }
        .buttonStyle(.plain)
    }

    private var identitySection: some View {
        Section {
            HStack(spacing: 14) {
                logoPicker

                TextField("Project name", text: $draft.name)
                    .font(ShioFont.bodyEmphasis)
                    .submitLabel(.done)

                if draft.imageData != nil {
                    Button {
                        draft.imageData = nil
                        photoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(ShioTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("A project is a workspace — give it a logo if you like, then add the repos and context that live under it.")
        }
    }

    private var reposSection: some View {
        Section {
            ForEach(draft.repos) { repo in RepoRow(repo: repo) }
                .onDelete { draft.repos.remove(atOffsets: $0) }
            if hosts.isEmpty {
                // Not a disabled button with homework — the fix, in place.
                // `hosts` is a live @Query, so finishing the pairing flips
                // this section to the normal repo-add state without leaving.
                Button { pairing = true } label: {
                    Label("Pair your first machine…", systemImage: "qrcode.viewfinder")
                }
            } else {
                Button { editingRepo = true } label: {
                    Label(draft.repos.isEmpty ? "Add a repo" : "Add another repo",
                          systemImage: "plus.circle.fill")
                }
            }
        } header: {
            Text("Repos")
        } footer: {
            Text(hosts.isEmpty
                 ? "Repos live on machines. Pair one now, or create the project and add them later."
                 : "Add as many as the project spans, across any of your machines — or none for now.")
        }
    }

    private var groundingSection: some View {
        Section {
            DisclosureGroup(isExpanded: $groundingExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MEMORY").font(ShioFont.footnote).foregroundStyle(ShioTheme.textTertiary)
                    TextField("What this project is, conventions, links the agent should read…",
                              text: $draft.memory, axis: .vertical)
                        .font(ShioFont.callout)
                        .lineLimit(3...10)
                }
                .padding(.vertical, 4)

                ForEach($draft.skills) { $skill in
                    TextField("Skill name", text: $skill.name)
                        .font(ShioFont.callout)
                }
                .onDelete { draft.skills.remove(atOffsets: $0) }

                Button { draft.skills.append(SkillSpec()) } label: {
                    Label("Add a skill", systemImage: "plus")
                }
                .font(ShioFont.callout)
            } label: {
                Label("Memory & skills", systemImage: "sparkles")
            }
        } footer: {
            Text("Grounding travels with the project — every agent you start here begins with the same context.")
        }
    }

    private func create() {
        Project.build(from: draft,
                      resolveHost: { id in hosts.first { $0.persistentModelID == id } },
                      in: context)
        dismiss()
    }
}

/// A repo as it appears in the draft list: source glyph, name, and machine·path.
private struct RepoRow: View {
    let repo: RepoSpec
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: repo.cloneURL != nil ? "arrow.down.circle" : "folder")
                .foregroundStyle(ShioTheme.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name).font(ShioFont.body)
                Text("\(repo.machineLabel) · \(repo.path)")
                    .font(ShioFont.Mono.inline)
                    .foregroundStyle(ShioTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}

/// Define one repo: which machine, and a folder on it or a git URL to clone.
/// Produces a `RepoSpec` for the draft (or commits straight to a project).
private struct RepoEditor: View {
    let hosts: [Host]
    var title: String = "Add a repo"
    var onSave: (RepoSpec) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Source: String, CaseIterable {
        case path = "On machine"
        case clone = "Clone URL"
    }

    @State private var selectedHost: Host?
    @State private var path = ""
    @State private var source: Source = .path
    @State private var gitURL = ""
    @State private var pairing = false

    private var trimmedPath: String { path.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { gitURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canAdd: Bool {
        guard selectedHost != nil, !trimmedPath.isEmpty else { return false }
        if source == .clone, trimmedURL.isEmpty { return false }
        return true
    }

    var body: some View {
        Form {
            if hosts.isEmpty {
                // The fix in place, not a dead paragraph pointing elsewhere —
                // `hosts` is live, so pairing completion reveals the editor.
                Section {
                    Button { pairing = true } label: {
                        Label("Pair your first machine…", systemImage: "qrcode.viewfinder")
                    }
                } footer: {
                    Text("Repos live on machines. Pair one and this editor unlocks.")
                }
            } else {
                Section("Machine") {
                    Picker("Host", selection: $selectedHost) {
                        ForEach(hosts.dedupedByIdentity) { host in
                            Text(host.name).tag(host as Host?)
                        }
                    }
                }
                Section {
                    Picker("Source", selection: $source) {
                        ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
                        Text("Shio runs git clone on the machine, using its own git auth, the first time you open it.")
                    }
                    Section {
                        TextField("/Users/you/code/your-repo", text: $path)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(ShioFont.Mono.inline)
                    } header: {
                        Text("Clone into")
                    } footer: {
                        Text("Absolute path on the machine to clone into.")
                    }
                } else {
                    Section {
                        NavigationLink {
                            if let host = selectedHost {
                                DirectoryPickerView(host: host,
                                                    initialPath: trimmedPath.isEmpty ? nil : trimmedPath) {
                                    path = $0
                                }
                            }
                        } label: {
                            HStack {
                                Text("Folder").foregroundStyle(ShioTheme.textPrimary)
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
                        Text("Browse the machine and pick the repo folder.")
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { commit() }.disabled(!canAdd)
            }
        }
        .onAppear { if selectedHost == nil { selectedHost = hosts.dedupedByIdentity.first } }
        .sheet(isPresented: $pairing) { PairingView() }
    }

    private func commit() {
        guard let host = selectedHost else { return }
        let leaf = (trimmedPath as NSString).lastPathComponent
        let name = leaf.isEmpty ? trimmedPath : leaf
        let cloneURL = (source == .clone && !trimmedURL.isEmpty) ? trimmedURL : nil
        onSave(RepoSpec(name: name, path: trimmedPath,
                        hostID: host.persistentModelID, cloneURL: cloneURL,
                        machineLabel: host.name))
        dismiss()
    }
}
