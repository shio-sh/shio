import SwiftUI
import SwiftData

/// Minimal v1 add-project: pick a host you've connected and point at a repo
/// path on it. Repo auto-discovery and clone-by-URL come next in Phase 2.
struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Host.name) private var hosts: [Host]

    @State private var selectedHost: Host?
    @State private var path: String = ""

    private var trimmedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                if hosts.isEmpty {
                    Section {
                        Text("Add a machine in the Hosts tab first, then come back to add a project on it.")
                            .font(ShioFont.callout)
                            .foregroundStyle(ShioColor.Text.secondary)
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
                        TextField("/Users/you/code/your-repo", text: $path)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(ShioFont.Mono.inline)
                    } header: {
                        Text("Repo path")
                    } footer: {
                        Text("The absolute path to the repo on that machine. Shio opens a terminal here.")
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
                        .disabled(selectedHost == nil || trimmedPath.isEmpty)
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
        let project = Project(name: name, path: trimmedPath, host: host)
        context.insert(project)
        try? context.save()
        dismiss()
    }
}
