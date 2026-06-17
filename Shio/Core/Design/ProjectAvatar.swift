import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// How a project is represented everywhere — overview cards, the switcher, the
/// Mac rail. Its logo image if one is set, otherwise the identity tint mark
/// (first letter on a stable per-project color), so a project always looks
/// intentional whether or not it has a logo.
struct ProjectAvatar: View {
    let name: String
    let imageData: Data?
    var size: CGFloat = 30

    private var radius: CGFloat { max(6, size * 0.24) }

    nonisolated init(_ project: Project, size: CGFloat = 30) {
        self.name = project.name
        self.imageData = project.imageData
        self.size = size
    }
    nonisolated init(name: String, imageData: Data?, size: CGFloat = 30) {
        self.name = name
        self.imageData = imageData
        self.size = size
    }

    var body: some View {
        Group {
            if let imageData, let image = Self.image(from: imageData) {
                image.resizable().scaledToFill()
            } else {
                ProjectIdentity.wash(for: name)
                    .overlay(
                        Text(String(name.first ?? "•").uppercased())
                            .font(.system(size: size * 0.46, weight: .medium, design: .monospaced))
                            .foregroundStyle(ProjectIdentity.color(for: name))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A SwiftUI `Image` from stored data, on either platform.
    static func image(from data: Data) -> Image? {
        #if os(macOS)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }

    /// Downscale + JPEG-encode an image to keep it small (CloudKit-friendly).
    /// Used by the logo pickers; `nonisolated` so it can run off the main actor.
    /// `maxDimension` caps the longest side.
    nonisolated static func encode(_ data: Data, maxDimension: CGFloat = 256) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #else
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)
        #endif
    }
}
