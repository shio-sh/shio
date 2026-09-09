import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// "Your data" — export it, or erase it.
///
/// One view used by both the iPhone/iPad settings and the Mac settings window,
/// so the two cannot drift into offering different answers to the same
/// question. The wording is deliberately concrete: it names what is in the
/// file, what is not, and exactly how much is about to be destroyed.
struct YourDataSection: View {
    @Environment(\.modelContext) private var context

    @State private var exportDocument: ArchiveDocument?
    @State private var showingExporter = false
    @State private var showingEraseConfirm = false
    @State private var failure: String?
    @State private var erasedJustNow = false

    var body: some View {
        Group {
            Button {
                prepareExport()
            } label: {
                Label("Export a backup…", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                showingEraseConfirm = true
            } label: {
                Label("Erase all Shio data…", systemImage: "trash")
            }

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: DataArchive.suggestedFilename()
        ) { result in
            if case .failure(let error) = result {
                failure = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Erase all Shio data?",
            isPresented: $showingEraseConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase \(counts.summary)", role: .destructive) { erase() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("""
            This removes \(counts.summary) from Shio on this device and every \
            device signed into the same iCloud account.

            Nothing on your machines is touched. No repository, file or tmux \
            session is affected, and your SSH key is kept, so hosts you have \
            already set up will still recognise this device.

            This cannot be undone. Export a backup first if you might want it.
            """)
        }
        .alert("Something went wrong", isPresented: .init(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .alert("Erased", isPresented: $erasedJustNow) {
            Button("OK") { erasedJustNow = false }
        } message: {
            Text("Shio is back to a clean slate. Your machines and their files were not touched.")
        }
    }

    private var counts: DataArchive.Counts { DataArchive.counts(in: context) }

    private var footnote: String {
        "The backup holds your projects, repos and machines as readable JSON. "
        + "It never contains your SSH keys, key passphrases or anything from your terminal."
    }

    private func prepareExport() {
        do {
            exportDocument = ArchiveDocument(data: try DataArchive.export(from: context))
            showingExporter = true
        } catch {
            failure = "The backup could not be created. \(error.localizedDescription)"
        }
    }

    private func erase() {
        do {
            try DataArchive.eraseAll(in: context)
            erasedJustNow = true
        } catch {
            // Deliberately surfaced rather than logged. A reset that silently
            // half-worked is worse than one that says it failed.
            failure = "Not everything could be erased. \(error.localizedDescription)"
        }
    }
}

/// Wraps the encoded archive for `fileExporter`, which wants a document type
/// rather than raw `Data`.
struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
