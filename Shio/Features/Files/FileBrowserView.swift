import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

/// SFTP file browser for one host. Navigate directories, preview/download
/// files, create folders, rename, delete, and upload.
struct FileBrowserView: View {
    @State private var vm: FilesViewModel

    @State private var previewFile: SFTPFile?
    @State private var renameTarget: SFTPFile?
    @State private var renameText = ""
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var showingUpload = false
    @State private var showingPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []

    init(host: Host, startPath: String? = nil) {
        _vm = State(initialValue: FilesViewModel(host: host, startPath: startPath))
    }

    var body: some View {
        content
            .background(ShioTheme.background)
            .navigationTitle(titleComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { if vm.entries.isEmpty { await vm.start() } }
            .onDisappear { Task { await vm.stop() } }
            .sheet(item: $previewFile) { file in
                FilePreviewView(vm: vm, file: file)
            }
            .sheet(isPresented: $showingUpload) {
                DocumentPicker { url in
                    Task {
                        if let data = try? Data(contentsOf: url) {
                            await vm.upload(data, name: url.lastPathComponent)
                        }
                    }
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection, maxSelectionCount: 10, matching: .images)
            .onChange(of: photoSelection) { _, items in
                guard !items.isEmpty else { return }
                let picked = items
                photoSelection = []
                Task { await uploadPhotos(picked) }
            }
            .alert("New folder", isPresented: $showingNewFolder) {
                TextField("Name", text: $newFolderName)
                    .textInputAutocapitalization(.never)
                Button("Create") {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    newFolderName = ""
                    if !name.isEmpty { Task { await vm.makeDirectory(named: name) } }
                }
                Button("Cancel", role: .cancel) { newFolderName = "" }
            }
            .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
                TextField("Name", text: $renameText)
                    .textInputAutocapitalization(.never)
                Button("Rename") {
                    if let file = renameTarget {
                        let name = renameText.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty, name != file.name { Task { await vm.rename(file, to: name) } }
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
    }

    private var titleComponent: String {
        let leaf = (vm.path as NSString).lastPathComponent
        return leaf.isEmpty ? "/" : leaf
    }

    /// Upload picked photos to the current directory. PhotosPicker carries no
    /// filename, so we synthesize one from the item's content type (png for
    /// screenshots, jpg/heic for camera shots).
    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        let stamp = Int(Date().timeIntervalSince1970)
        for (i, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "img"
            let name = items.count == 1 ? "shio-\(stamp).\(ext)" : "shio-\(stamp)-\(i + 1).\(ext)"
            await vm.upload(data, name: name)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .connecting:
            VStack(spacing: ShioSpace.md) {
                ProgressView().controlSize(.large)
                Text("Connecting to \(vm.hostName)…")
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: ShioSpace.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(ShioTheme.warning)
                Text(message)
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textSecondary)
                    .multilineTextAlignment(.center)
                LegacyButton("Retry") { Task { await vm.start() } }
            }
            .padding(ShioSpace.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .browsing:
            fileList
        }
    }

    private var fileList: some View {
        List {
            if vm.entries.isEmpty {
                Text("Empty folder")
                    .font(ShioFont.callout)
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            ForEach(vm.entries) { file in
                Button {
                    if file.isDirectory { Task { await vm.open(file) } }
                    else { previewFile = file }
                } label: {
                    FileRow(file: file)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await vm.delete(file) }
                    } label: { Label("Delete", systemImage: "trash") }
                    Button {
                        renameText = file.name
                        renameTarget = file
                    } label: { Label("Rename", systemImage: "pencil") }
                    .tint(.gray)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.refresh() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if vm.canGoUp {
                Button { Task { await vm.goUp() } } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityLabel("Parent folder")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button { showingNewFolder = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                Button { showingPhotoPicker = true } label: { Label("Upload Photo", systemImage: "photo") }
                Button { showingUpload = true } label: { Label("Upload File", systemImage: "arrow.up.doc") }
                Button { Task { await vm.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

private struct FileRow: View {
    let file: SFTPFile

    var body: some View {
        HStack(spacing: ShioSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(file.isDirectory ? ShioTheme.textPrimary : ShioTheme.textSecondary)
                .frame(width: 24)
            Text(file.name)
                .font(ShioFont.body)
                .foregroundStyle(ShioTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let size = file.attributes.size, !file.isDirectory {
                Text(byteString(size))
                    .font(ShioFont.footnote)
                    .foregroundStyle(ShioTheme.textTertiary)
            }
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        if file.isDirectory { return "folder.fill" }
        if file.attributes.isSymlink { return "arrow.up.right.square" }
        return "doc"
    }

    private func byteString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Document picker (upload)

private struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
