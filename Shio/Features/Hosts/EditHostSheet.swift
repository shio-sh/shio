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
    @State private var saveError: String?

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
                        You changed the address. Host keys are pinned per \
                        address, so Shio has nothing pinned for the new one \
                        and will trust whatever answers the first time it \
                        connects, exactly as it did when you first added this \
                        machine. Make sure the address is right.
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
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
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
        // The new hostname is computed first: the fallback used to read
        // `host.hostname` one line before it was overwritten, so clearing the
        // display name while changing the address named the machine after the
        // address it no longer pointed at.
        let newHostname = hostname.trimmingCharacters(in: .whitespaces)
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        host.name = trimmedName.isEmpty ? newHostname : trimmedName
        host.hostname = newHostname
        host.username = username.trimmingCharacters(in: .whitespaces)
        if let p = Int(port) { host.port = p }
        let jump = proxyJump.trimmingCharacters(in: .whitespaces)
        host.proxyJump = jump.isEmpty ? nil : jump
        host.persistenceMode = persistenceMode
        do {
            try context.save()
            dismiss()
        } catch {
            // Was a discarded `try` with a comment claiming the caller handled
            // it. No caller did, so a failed save dismissed the sheet as though
            // it had worked and the correction was gone.
            saveError = error.localizedDescription
        }
    }
}
