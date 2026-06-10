import Foundation
import SwiftData

/// The inverse of `SkillMaterializer`: pulls skills that already exist on disk
/// (the ones agents use today) INTO Shio, so they become managed, CloudKit-
/// synced, and materialized onto the user's *other* machines — edit on the
/// phone, it lands everywhere. v3 (#39).
///
/// Dedup is by name (case-insensitive); an existing Shio skill is never
/// overwritten by an import. The frontmatter parser is shared by the local
/// (Mac) scan and the remote (SSH) scan.
@MainActor
enum SkillImporter {

    /// `(name, description, body)` pulled out of a `SKILL.md`.
    struct Parsed: Equatable { let name: String; let description: String; let body: String }

    /// Split `--- … ---` YAML frontmatter (just `name` / `description`) from the
    /// markdown body. Falls back to the directory name when there's no `name:`.
    static func parse(_ text: String, fallbackName: String) -> Parsed {
        var name = fallbackName, desc = ""
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<close] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if key == "name", !val.isEmpty { name = val }
                if key == "description" { desc = val }
            }
            body = lines[(close + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Parsed(name: name, description: desc, body: body)
    }

    /// Upsert parsed skills as global records, skipping names Shio already has.
    /// Returns the number newly imported.
    @discardableResult
    static func upsertGlobals(_ parsed: [Parsed], into context: ModelContext) -> Int {
        var existing = Set(((try? context.fetch(FetchDescriptor<Skill>())) ?? [])
            .filter(\.isGlobal).map { $0.name.lowercased() })
        var imported = 0
        for p in parsed where !p.name.isEmpty {
            let key = p.name.lowercased()
            if existing.contains(key) { continue }     // never overwrite an existing skill
            context.insert(Skill(name: p.name, skillDescription: p.description, content: p.body))
            existing.insert(key)
            imported += 1
        }
        if imported > 0 { try? context.save() }
        return imported
    }

    #if os(macOS)
    /// Scan this Mac's agent skill dirs and import any global skills not already
    /// in Shio. Returns how many were imported.
    @discardableResult
    static func importLocal(into context: ModelContext) -> Int {
        let home = NSHomeDirectory()
        let dirs = [".claude/skills", ".agents/skills", ".cursor/skills", ".codex/skills"].map { "\(home)/\($0)" }
        let fm = FileManager.default
        var parsed: [Parsed] = []
        var seen = Set<String>()
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries.sorted() {
                let file = "\(dir)/\(entry)/SKILL.md"
                guard fm.fileExists(atPath: file),
                      let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
                let p = parse(text, fallbackName: entry)
                if seen.insert(p.name.lowercased()).inserted { parsed.append(p) }
            }
        }
        return upsertGlobals(parsed, into: context)
    }
    #endif
}
