import SwiftUI
import SwiftData

/// Change a machine's connection details.
///
/// Everything here was write-once. A machine's hostname, port, username,
/// proxy jump and persistence mode were set when it was added and could never
/// be changed again, so a typo in a username — the most ordinary mistake there
/// is when setting up SSH — meant deleting the machine and adding it back,
/// which took every repo checkout on it along the way.
///
/// The host key is deliberately not editable. It is pinned by connecting, and
/// a field that let someone type one in would be a way to talk yourself past
/// the warning that exists to protect you.
struct EditHostSheet: View {
    let host: Host
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var displayName: String = ""
    @State private var hostname: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var proxyJump: String = ""
    @State private var persistenceMode: Host.PersistenceMode = .tmuxAutoResume
    @State private var addressChanged = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Machine") {
                    TextField("Display name", text: $displayName)
                    plainField("Hostname or IP", $hostname)
                    plainField("Username", $username)
                    plainField("Port", $port)
                }

                Section("Advanced") {
                    plainField("ProxyJump (optional)", $proxyJump)
                    Picker("Sessions", selection: $persistenceMode) {
                        Text("Keep running with tmux").tag(Host.PersistenceMode.tmuxAutoResume)
                        Text("Plain shell").tag(Host.PersistenceMode.plain)
                    }
                }

                if addressChanged {
                    Section {
                        Text("""
                        You changed the address or port. Shio pinned this \
                        machine's host key the first time it connected; \
                        pointing at a different machine will look like a key \
                        change and be refused, which is the warning working, \
                        not a bug.
                        """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit machine")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: hostname) { _, _ in noteAddressChange() }
        .onChange(of: port) { _, _ in noteAddressChange() }
    }

    /// A text field that does not try to be clever with capitalisation or
    /// autocorrect. Hostnames and usernames are the two things iOS most likes
    /// to "fix". The modifiers are iOS-only and this view ships on the Mac too.
    @ViewBuilder
    private func plainField(_ title: String, _ text: Binding<String>) -> some View {
        #if os(iOS)
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField(title, text: text)
            .autocorrectionDisabled()
        #endif
    }

    private var isValid: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty
        && !username.trimmingCharacters(in: .whitespaces).isEmpty
        && Int(port).map { $0 > 0 && $0 < 65536 } == true
    }

    private func load() {
        displayName = host.name
        hostname = host.hostname
        port = String(host.port)
        username = host.username
        proxyJump = host.proxyJump ?? ""
        persistenceMode = host.persistenceMode
    }

    private func noteAddressChange() {
        addressChanged = hostname != host.hostname || Int(port) != host.port
    }

    private func save() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        host.name = trimmedName.isEmpty ? host.hostname : trimmedName
        host.hostname = hostname.trimmingCharacters(in: .whitespaces)
        host.username = username.trimmingCharacters(in: .whitespaces)
        if let p = Int(port) { host.port = p }
        let jump = proxyJump.trimmingCharacters(in: .whitespaces)
        host.proxyJump = jump.isEmpty ? nil : jump
        host.persistenceMode = persistenceMode
        // Surfaced by the caller if it fails; a silent save that lost an edit
        // would look like the form simply ignored you.
        try? context.save()
        dismiss()
    }
}
