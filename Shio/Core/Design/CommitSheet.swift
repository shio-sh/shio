import SwiftUI

/// Stage → commit → push a checkout, with the exact command shown before it
/// runs. Shared by the Mac and iOS dashboards; `config == nil` means the
/// checkout is local (Mac), otherwise it runs over SSH.
struct CommitSheet: View {
    let repoName: String
    let dirtyCount: Int
    let path: String
    let config: SSHClient.Configuration?
    var onCommitted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var running = false
    @State private var resultText: String?
    @State private var didFail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Commit & push").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ShioTheme.textPrimary)
                Text(repoName).font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(ShioTheme.textSecondary)
                Spacer()
                if dirtyCount > 0 {
                    HStack(spacing: 5) { ShioStatusDot(status: .warning, size: 7)
                        Text("\(dirtyCount)").font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(ShioTheme.warning) }
                }
            }

            TextField("Commit message", text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ShioTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ShioTheme.line, lineWidth: 1))

            Text("will run").font(ShioKitFont.label).tracking(1).textCase(.uppercase)
                .foregroundStyle(ShioTheme.textTertiary)
            Text(GitWriter.previewCommand(message: message.isEmpty ? "…" : message))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShioTheme.textSecondary)
                .lineLimit(3).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ShioTheme.hover))

            if let resultText {
                Text(resultText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(didFail ? ShioTheme.danger : ShioTheme.success)
                    .lineLimit(4)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                ShioButton(running ? "Pushing…" : "Commit & push", .primary, icon: "arrow.up") { run() }
                    .disabled(running || message.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 460)
        .background(ShioTheme.background)
    }

    private func run() {
        running = true; resultText = nil
        let msg = message.trimmingCharacters(in: .whitespaces)
        Task {
            let outcome = await GitWriter.commitAndPush(path: path, config: config, message: msg)
            running = false
            switch outcome {
            case .ok(let text): didFail = false; resultText = text; onCommitted()
            case .failed(let why): didFail = true; resultText = why
            }
        }
    }
}
