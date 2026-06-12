import SwiftUI

/// Browse a host over SFTP and pick a directory — used by AddProjectSheet so
/// you choose a repo folder by navigating the machine instead of typing its
/// path. Reuses `FilesViewModel` for navigation; no file management here.
/// Navigate into a folder, then "Use this folder" selects the current path.
struct DirectoryPickerView: View {
    @State private var vm: FilesViewModel
    @Environment(\.dismiss) private var dismiss
    private let onSelect: (String) -> Void

    init(host: Host, initialPath: String? = nil, onSelect: @escaping (String) -> Void) {
        _vm = State(initialValue: FilesViewModel(host: host, startPath: initialPath))
        self.onSelect = onSelect
    }

    var body: some View {
        content
            .background(ShioTheme.background)
            .navigationTitle(titleComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if vm.canGoUp {
                        Button { Task { await vm.goUp() } } label: {
                            Image(systemName: "chevron.up")
                        }
                        .accessibilityLabel("Parent folder")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if case .browsing = vm.state {
                    VStack(spacing: 0) {
                        Divider()
                        LegacyButton("Use this folder") {
                            onSelect(vm.path)
                            dismiss()
                        }
                        .padding(ShioSpace.md)
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .task { if vm.entries.isEmpty { await vm.start() } }
            .onDisappear { Task { await vm.stop() } }
    }

    private var titleComponent: String {
        let leaf = (vm.path as NSString).lastPathComponent
        return leaf.isEmpty ? "/" : leaf
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
            List {
                if vm.entries.allSatisfy({ !$0.isDirectory }) {
                    Text("No subfolders here — use the button below to pick this folder.")
                        .font(ShioFont.footnote)
                        .foregroundStyle(ShioTheme.textTertiary)
                }
                ForEach(vm.entries) { file in
                    if file.isDirectory {
                        Button { Task { await vm.open(file) } } label: {
                            row(for: file, enabled: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(for: file, enabled: false)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for file: SFTPFile, enabled: Bool) -> some View {
        HStack(spacing: ShioSpace.md) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 18))
                .foregroundStyle(enabled ? ShioTheme.textPrimary : ShioTheme.textTertiary)
                .frame(width: 24)
            Text(file.name)
                .font(ShioFont.body)
                .foregroundStyle(enabled ? ShioTheme.textPrimary : ShioTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShioTheme.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
