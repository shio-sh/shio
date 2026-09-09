import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A project logo control on the Mac: shows the avatar, and lets you set a logo
/// by clicking (file open-panel) or dragging an image onto it, or remove it via
/// the corner badge / right-click. Calls `onPick` with the resized-and-encoded
/// image data, or `nil` to clear. Used by the create form and the project header.
struct MacLogoWell: View {
    let name: String
    let imageData: Data?
    var size: CGFloat = 56
    var showsBadge: Bool = true
    var onPick: (Data?) -> Void

    @State private var targeted = false

    private var radius: CGFloat { max(6, size * 0.24) }

    var body: some View {
        ProjectAvatar(name: name.isEmpty ? "?" : name, imageData: imageData, size: size)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(targeted ? ShioTheme.accent : .clear, lineWidth: 2)
            )
            .overlay(alignment: .bottomTrailing) {
                if showsBadge {
                    // A Button, not a tap gesture on an Image: the gesture
                    // version could not be focused with a keyboard or reached
                    // by VoiceOver at all.
                    Button { imageData == nil ? choose() : onPick(nil) } label: {
                        Image(systemName: imageData == nil ? "pencil.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 17))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(ShioTheme.textSecondary, ShioTheme.surface)
                            .offset(x: 4, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(imageData == nil ? "Choose a logo" : "Remove the logo")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { choose() }
            .accessibilityLabel(name.isEmpty ? "Project logo" : "\(name) logo")
            .accessibilityHint("Choose a logo, or drag an image here")
            .help("Click to choose a logo, or drag an image here")
            .contextMenu {
                Button(imageData == nil ? "Set Logo…" : "Change Logo…") { choose() }
                if imageData != nil { Button("Remove Logo") { onPick(nil) } }
            }
            .onDrop(of: [.image, .fileURL], isTargeted: $targeted) { handleDrop($0) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose"
        panel.message = "Pick a logo image for this project."
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            onPick(ProjectAvatar.encode(data))
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage, let tiff = image.tiffRepresentation else { return }
                DispatchQueue.main.async { onPick(ProjectAvatar.encode(tiff)) }
            }
            return true
        }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let path = String(data: data, encoding: .utf8),
                  let url = URL(string: path), let bytes = try? Data(contentsOf: url) else { return }
            DispatchQueue.main.async { onPick(ProjectAvatar.encode(bytes)) }
        }
        return true
    }
}
