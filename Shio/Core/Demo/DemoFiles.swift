import Foundation

/// A canned, navigable SFTP tree for the demo Files browser — rooted in the
/// Ekpani projects so it matches the seeded machines/projects. Used only when
/// ``DemoMode/isActive``; `FilesViewModel` swaps real SFTP for this.
enum DemoFiles {

    /// Listing for a directory path. Folders first, then files, alphabetical.
    static func tree(at path: String) -> [SFTPFile] {
        let name = (path as NSString).lastPathComponent
        let entries: [SFTPFile]
        switch name {
        case "amrith", "":          // home
            entries = [dir("shio"), dir("timebase"), dir("samooh"), dir("stem"),
                       dir("medivalent"), dir("pasture"),
                       file(".zshrc", 2_140), file(".gitconfig", 384), file("notes.md", 8_204)]
        case "shio":       entries = [dir("shio-app"), dir("landing"), dir("beta-worker"), file("README.md", 1_920)]
        case "timebase":   entries = [dir("timebase-app"), dir("api"), file("README.md", 1_440)]
        case "samooh":     entries = [dir("samooh-web"), dir("dhuni"), dir("biriyani"), file("README.md", 1_710)]
        case "stem":       entries = [dir("stem-app"), dir("crawler"), file("README.md", 1_280)]
        case "medivalent": entries = [dir("medivalent"), file("README.md", 1_180)]
        case "pasture":    entries = [dir("pasture-app"), dir("worker"), file("README.md", 990)]
        case "Sources", "src":
            entries = [dir("Features"), dir("Core"), file("App.swift", 1_204), file("RootView.swift", 3_180)]
        default:           // a repo directory
            entries = [dir("Sources"), dir("Tests"),
                       file("Package.swift", 1_640), file("project.yml", 2_980),
                       file("README.md", 2_210), file(".gitignore", 412)]
        }
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Readable content for a file preview.
    static func content(for name: String) -> Data {
        let text: String
        switch (name as NSString).pathExtension {
        case "md":
            text = "# \((name as NSString).deletingPathExtension)\n\nBuilt under Ekpani, one leaf at a time.\n"
        case "swift":
            text = "import Foundation\n\n// \(name)\nstruct Demo {\n    let ok = true\n}\n"
        case "json":
            text = "{\n  \"name\": \"\(name)\",\n  \"ok\": true\n}\n"
        case "yml":
            text = "name: Shio\noptions:\n  bundleIdPrefix: sh.shio\n"
        default:
            text = "\(name)\n"
        }
        return Data(text.utf8)
    }

    private static func dir(_ n: String) -> SFTPFile {
        SFTPFile(name: n, attributes: SFTPFileAttributes(size: nil, permissions: 0o040755, mtime: nil))
    }
    private static func file(_ n: String, _ size: UInt64) -> SFTPFile {
        SFTPFile(name: n, attributes: SFTPFileAttributes(size: size, permissions: 0o100644, mtime: nil))
    }
}
