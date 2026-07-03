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
                        Button {
                            pairing = true
                        } label: {
                            Label("Pair your first machine…", systemImage: "qrcode.viewfinder")
                        }
                    } footer: {
                        Text("\(repo.name) lives on a machine Shio can't reach yet. Pair one and this repo opens right after.")
                    }
                } else {
                    Section("Machine") {
                        Picker("Host", selection: $selectedHost) {
                            ForEach(hosts.dedupedByIdentity) { host in
                                Text(host.name).tag(host as Host?)
                            }
                        }
                    }
                    if clones {
                        Section {
                            TextField("/Users/you/code/\(repo.name)", text: $path)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(ShioFont.Mono.inline)
                        } header: {
                            Text("Clone into")
                        } footer: {
                            Text("Shio runs git clone on \(selectedHost?.name ?? "the machine"), using its own git auth, the first time you open it.")
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
                            Text("Browse \(selectedHost?.name ?? "the machine") and pick where \(repo.name) is checked out.")
                        }
                    }
                }
            }
            .navigationTitle("\(repo.name) isn’t on a machine yet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !hosts.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(clones ? "Clone here" : "Use folder") { place() }
                            .disabled(!canPlace)
                    }
                }
            }
            .onAppear { if selectedHost == nil { selectedHost = hosts.dedupedByIdentity.first } }
            .sheet(isPresented: $pairing) { PairingView() }
        }
    }

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
