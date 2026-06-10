import SwiftUI

/// Previews a file fetched over SFTP: shows text inline when it decodes as
/// UTF-8, otherwise reports it as binary. Either way you can share/save it
/// out via the system share sheet (writes to a temp file).
struct FilePreviewView: View {
    let vm: FilesViewModel
    let file: SFTPFile

    @Environment(\.dismiss) private var dismiss

    enum LoadState: Equatable {
        case loading
        case text(String, URL)
        case binary(Int, URL)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .text(let contents, _):
                    ScrollView([.vertical, .horizontal]) {
                        Text(contents)
                            .font(ShioFont.Mono.inline)
                            .foregroundStyle(ShioTheme.textPrimary)
                            .textSelection(.enabled)
                            .padding(ShioSpace.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .binary(let bytes, _):
                    VStack(spacing: ShioSpace.md) {
                        Image(systemName: "doc.fill")
                            .font(.largeTitle)
                            .foregroundStyle(ShioTheme.textSecondary)
                        Text("Binary file")
                            .font(ShioFont.title2)
                            .foregroundStyle(ShioTheme.textPrimary)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                            .font(ShioFont.callout)
                            .foregroundStyle(ShioTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    VStack(spacing: ShioSpace.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(ShioFont.callout)
                            .foregroundStyle(ShioTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(ShioSpace.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(ShioTheme.background)
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = sharedURL {
                        ShareLink(item: url)
                    }
                }
            }
            .task { await load() }
        }
    }

    private var sharedURL: URL? {
        switch loadState {
        case .text(_, let url), .binary(_, let url): return url
        default: return nil
        }
    }

    private func load() async {
        do {
            let data = try await vm.read(file)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try? data.write(to: url)
            if let text = String(data: data, encoding: .utf8) {
                loadState = .text(text, url)
            } else {
                loadState = .binary(data.count, url)
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
