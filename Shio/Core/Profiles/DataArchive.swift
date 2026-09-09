import Foundation
import SwiftData

/// Anything the archive sorts alphabetically.
protocol Named { var name: String { get } }
extension Host: Named {}
extension Project: Named {}
extension Repo: Named {}

/// Export everything Shio knows about you, and erase it.
///
/// Two things a person is entitled to and Shio had neither: a way to see and
/// keep what the app is storing, and a way to take it all back. Without them
/// the only exit from the app is deleting it and hoping, which is a poor answer
/// for something holding the map to your machines.
///
/// **What is in the archive.** Projects, the repos in them, where those repos
/// live, and the machines you have added. Enough to rebuild your setup by hand
/// on a new device, and readable enough to audit in any text editor.
///
/// **What is deliberately NOT in it.** Private keys, key passphrases, and host
/// key fingerprints. Keys live in the keychain and the Secure Enclave and are
/// not ours to copy into a file that lands in Downloads or a share sheet. A
/// leaked archive should be embarrassing, not dangerous. Host fingerprints are
/// public but are omitted anyway: re-pinning on first connect is the safer
/// default than importing a fingerprint from a file that could have been edited.
enum DataArchive {

    // MARK: The shape on disk

    /// Versioned so a future reader can tell what it is looking at. Bump only
    /// when the meaning of a field changes, not when one is added.
    static let formatVersion = 1

    struct Archive: Codable {
        var format: Int
        var exportedAt: Date
        var app: String
        var machines: [MachineRecord]
        var projects: [ProjectRecord]
        /// Says in the file itself what was left out, so someone reading it
        /// later does not assume the omission was an oversight.
        var omitted: [String]
    }

    struct MachineRecord: Codable {
        var name: String
        var hostname: String
        var port: Int
        var username: String
        var kind: String
        var persistenceMode: String
        var proxyJump: String?
        var addedAt: Date
        var lastConnectedAt: Date?
    }

    struct ProjectRecord: Codable {
        var name: String
        var cloneURL: String?
        var createdAt: Date
        var lastOpenedAt: Date?
        var repos: [RepoRecord]
    }

    struct RepoRecord: Codable {
        var name: String
        var cloneURL: String?
        var createdAt: Date
        /// Where this repo sits, one entry per machine it is checked out on.
        var checkouts: [CheckoutRecord]
    }

    struct CheckoutRecord: Codable {
        var machine: String?
        var path: String
    }

    // MARK: Export

    private static func byName<T>(_ a: T, _ b: T) -> Bool where T: Named {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    @MainActor
    static func export(from context: ModelContext) throws -> Data {
        let hosts = (try? context.fetch(FetchDescriptor<Host>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []

        var machines: [MachineRecord] = []
        for host in hosts.sorted(by: byName) {
            machines.append(
                MachineRecord(
                    name: host.name,
                    hostname: host.hostname,
                    port: host.port,
                    username: host.username,
                    kind: host.kindRaw,
                    persistenceMode: host.persistenceModeRaw,
                    proxyJump: host.proxyJump,
                    addedAt: host.createdAt,
                    lastConnectedAt: host.lastConnectedAt
                )
            )
        }

        // Built with explicit loops rather than nested map/sort chains: the
        // chained version compiled but took the type checker an absurd amount
        // of time, and a build that is slow for no reason is a tax on every
        // future change to this file.
        var projectRecords: [ProjectRecord] = []
        for project in projects.sorted(by: byName) {
            var repoRecords: [RepoRecord] = []
            for repo in (project.repos ?? []).sorted(by: byName) {
                var checkoutRecords: [CheckoutRecord] = []
                for checkout in repo.checkouts ?? [] {
                    checkoutRecords.append(
                        CheckoutRecord(machine: checkout.host?.name, path: checkout.path)
                    )
                }
                repoRecords.append(
                    RepoRecord(name: repo.name,
                               cloneURL: repo.cloneURL,
                               createdAt: repo.createdAt,
                               checkouts: checkoutRecords)
                )
            }
            projectRecords.append(
                ProjectRecord(name: project.name,
                              cloneURL: project.cloneURL,
                              createdAt: project.createdAt,
                              lastOpenedAt: project.lastOpenedAt,
                              repos: repoRecords)
            )
        }

        let archive = Archive(
            format: formatVersion,
            exportedAt: Date(),
            app: "Shio",
            machines: machines,
            projects: projectRecords,
            omitted: [
                "SSH private keys — they stay in the keychain and the Secure Enclave",
                "SSH key passphrases",
                "Host key fingerprints — re-pinned on the next connection",
                "Terminal scrollback and session contents — those live on your machines, never here",
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// `shio-backup-2026-09-09.json`. Dated, because the first thing anyone
    /// does with two backups is wonder which is newer.
    static func suggestedFilename(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "shio-backup-\(f.string(from: date)).json"
    }

    // MARK: Counts, for telling the truth before erasing

    struct Counts {
        var projects: Int
        var repos: Int
        var machines: Int

        /// "3 projects, 7 repos and 4 machines". Used in the confirmation, so
        /// the warning names what is actually about to go rather than saying
        /// "everything" and hoping.
        var summary: String {
            var parts: [String] = []
            if projects > 0 { parts.append("\(projects) project\(projects == 1 ? "" : "s")") }
            if repos > 0 { parts.append("\(repos) repo\(repos == 1 ? "" : "s")") }
            if machines > 0 { parts.append("\(machines) machine\(machines == 1 ? "" : "s")") }
            guard !parts.isEmpty else { return "nothing yet" }
            guard parts.count > 1 else { return parts[0] }
            return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }

    @MainActor
    static func counts(in context: ModelContext) -> Counts {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let hosts = (try? context.fetch(FetchDescriptor<Host>())) ?? []
        let repos = (try? context.fetch(FetchDescriptor<Repo>())) ?? []
        return Counts(projects: projects.count, repos: repos.count,
                      machines: hosts.filter(\.isConnectable).count)
    }

    // MARK: Reset

    /// Erase everything Shio stores about your setup.
    ///
    /// Deletes projects, repos, checkouts and machines, in that order, so no
    /// child is orphaned mid-way if the save fails. It does NOT touch anything
    /// on the machines themselves: no repository, no file and no tmux session
    /// is affected, because none of that was ever ours. The SSH key is left
    /// alone too, so the hosts you have already set up still recognise this
    /// device if you add them again.
    ///
    /// This syncs. Erasing here erases on every device signed into the same
    /// iCloud account, which is exactly why the caller must confirm first.
    @MainActor
    static func eraseAll(in context: ModelContext) throws {
        for project in (try? context.fetch(FetchDescriptor<Project>())) ?? [] {
            ModelCascade.delete(project: project, context: context)
        }
        for host in (try? context.fetch(FetchDescriptor<Host>())) ?? [] {
            ModelCascade.delete(host: host, context: context)
        }
        // Anything left behind by an older schema or an interrupted delete.
        for orphan in (try? context.fetch(FetchDescriptor<Repo>())) ?? [] {
            context.delete(orphan)
        }
        for orphan in (try? context.fetch(FetchDescriptor<ProjectCheckout>())) ?? [] {
            context.delete(orphan)
        }
        try context.save()
    }
}
