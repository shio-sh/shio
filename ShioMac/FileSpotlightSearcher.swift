import Foundation
import AppKit

/// One Spotlight file hit surfaced in the command palette.
struct FileHit: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    var isDirectory: Bool
}

/// Live file search across This Mac via Spotlight (`NSMetadataQuery`). Powers
/// the universal ⌘K palette's Files results. Unsandboxed, so it can query the
/// whole local index. Debounced; capped to a handful of most-recent matches.
@MainActor
@Observable
final class FileSpotlightSearcher {
    private(set) var results: [FileHit] = []

    private let query = NSMetadataQuery()
    private var debounce: Task<Void, Never>?

    init() {
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(metadataUpdated),
                           name: .NSMetadataQueryDidFinishGathering, object: query)
        center.addObserver(self, selector: #selector(metadataUpdated),
                           name: .NSMetadataQueryDidUpdate, object: query)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // NSMetadataQuery posts on the main thread, so this lands on the main actor.
    @objc private func metadataUpdated() { collect() }

    /// Update the search. Short queries clear results (Spotlight on 1 char is
    /// noise). Debounced so we don't restart the query on every keystroke.
    func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        debounce?.cancel()
        guard q.count >= 2 else { stop(); results = []; return }
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            self.query.stop()
            self.query.predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", q)
            self.query.start()
        }
    }

    func stop() {
        debounce?.cancel()
        if query.isStarted { query.stop() }
    }

    private func collect() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let items = (query.results as? [NSMetadataItem]) ?? []
        results = items.prefix(6).compactMap { item in
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? (path as NSString).lastPathComponent
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return FileHit(path: path, name: name, isDirectory: isDir.boolValue)
        }
    }
}
