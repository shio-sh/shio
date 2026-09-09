import SwiftUI
import SwiftData

/// The repair path for a repo with no checkout on a reachable machine —
/// previously a dead-end alert ("no machine for this repo"). Synced repos
/// arrive like this all the time: created on another device, not yet placed
/// anywhere this device can reach. The fix is one decision — where does it
/// live? Pick a machine and point at (or clone into) a folder; the checkout
/// is created and the existing open path takes over (clone-on-first-attach
/// included).
struct RepoRepairSheet: View {
    let repo: Repo
    /// Called with the fresh checkout once created — the caller opens it.
    var onRepaired: (ProjectCheckout) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var hosts: [Host]

    @State private var selectedHost: Host?
    @State private var path = ""
    @State private var pairing = false

    private var trimmedPath: String { path.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canPlace: Bool { selectedHost != nil && !trimmedPath.isEmpty }
    private var clones: Bool { repo.cloneURL?.isEmpty == false }

    var body: some View {
        NavigationStack {
            Form {
                if hosts.isEmpty {
                    // No machines at all — the repair starts one level up.
                    Section {
                        #if os(iOS)
                        Button {
                            pairing = true
                        } label: {
                            Label("Pair your first machine…", systemImage: "qrcode.viewfinder")
                        }
                        #else
                        // The Mac adds machines from its own Machines canvas
                        // (⇧⌘M), so point there rather than ship a second flow.
                        Label("Add a machine first — Machines (⇧⌘M)",
                              systemImage: "desktopcomputer")
                            .foregroundStyle(ShioTheme.textSecondary)
                        #endif
                    } footer: {
                        Text("\(repo.name) lives on a machine Shio can't reach yet. Add one and this repo opens right after.")
                    }
                } else {
                    Section("Machine") {
                        Picker("Machine", selection: $selectedHost) {
                            ForEach(hosts.connectable.dedupedByIdentity) { host in
                                Text(host.name).tag(host as Host?)
                            }
                        }
                    }
                    if clones {
                        Section {
                            pathField
                        } header: {
                            Text("Clone into")
                        } footer: {
                            Text("Shio runs git clone on \(selectedHost?.name ?? "the machine"), using its own git auth, the first time you open it.")
                        }
                    } else {
                        Section {
                            #if os(iOS)
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
                            #else
                            // The Mac's SFTP browser isn't a pushable view here,
                            // so type the path; a local machine gets Browse…
                            HStack {
                                pathField
                                if isLocalSelection {
                                    Button("Browse…") { browseLocalFolder() }
                                }
                            }
                            #endif
                        } header: {
                            Text("Repo folder")
                        } footer: {
                            Text("Browse \(selectedHost?.name ?? "the machine") and pick where \(repo.name) is checked out.")
                        }
                    }
                }
            }
            .navigationTitle("\(repo.name) isn’t on a machine yet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !hosts.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(clones ? "Clone here" : "Use folder") { place() }
                            .disabled(!canPlace)
                    }
                }
            }
            .onAppear { if selectedHost == nil { selectedHost = hosts.connectable.dedupedByIdentity.first } }
            #if os(iOS)
            .sheet(isPresented: $pairing) { PairingView() }
            #endif
        }
    }

    /// The path field, shared by the clone-into and pick-a-folder cases.
    /// Autocapitalization is an iOS-only modifier.
    private var pathField: some View {
        let field = TextField("/Users/you/code/\(repo.name)", text: $path)
            .autocorrectionDisabled()
            .font(ShioFont.Mono.inline)
        #if os(iOS)
        return field.textInputAutocapitalization(.never)
        #else
        return field
        #endif
    }

    #if os(macOS)
    /// True when the chosen machine is this Mac, where a real folder picker beats
    /// typing a path.
    private var isLocalSelection: Bool { MacSelfHost.isThisMac(selectedHost) }

    private func browseLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use folder"
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
    #endif

    private func place() {
        guard let host = selectedHost else { return }
        let checkout = ProjectCheckout(path: trimmedPath, project: repo.project, host: host)
        checkout.repo = repo
        checkout.lastOpenedAt = .now
        context.insert(checkout)
        try? context.save()
        dismiss()
        onRepaired(checkout)
    }
}
