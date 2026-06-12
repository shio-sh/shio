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
        // Normalize CRLF first: a Windows-edited SKILL.md leaves \r on every
        // line, the "---" fences never match, and the frontmatter gets
        // imported as body — then doubled on the next re-materialize.
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
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

    // MARK: - Remote import (the cross-machine half)

    private static let skMarker = "__SK__", sbMarker = "__SB__", seMarker = "__SE__"

    /// Scan a machine's agent skill dirs over one SSH connection and import the
    /// global skills not already in Shio. Each pane is base64'd so arbitrary
    /// content survives the shell. Returns how many were imported.
    @discardableResult
    static func importRemote(config: SSHClient.Configuration, into context: ModelContext) async -> Int {
        let script = """
        for base in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.cursor/skills" "$HOME/.codex/skills"; do
          [ -d "$base" ] || continue
          for d in "$base"/*/; do
            f="${d}SKILL.md"
            [ -f "$f" ] || continue
            printf '\(skMarker)%s\(sbMarker)' "$(basename "$d")"
            base64 < "$f" | tr -d '\\n'
            printf '\(seMarker)'
          done
        done
        """
        let client = SSHClient(configuration: config)
        var out = ""
        do {
            try await client.connect()
            out = (try? await client.exec(script, timeout: .seconds(10))) ?? ""
            await client.disconnect()
        } catch {
            await client.disconnect()
            return 0
        }
        return upsertGlobals(parseRemoteScan(out), into: context)
    }

    /// Pull `<dirname>` + base64 body out of each marked block and parse it.
    static func parseRemoteScan(_ out: String) -> [Parsed] {
        var result: [Parsed] = []
        var seen = Set<String>()
        for chunk in out.components(separatedBy: skMarker).dropFirst() {
            guard let bR = chunk.range(of: sbMarker) else { continue }
            let dirName = String(chunk[..<bR.lowerBound])
            let after = chunk[bR.upperBound...]
            let b64 = (after.components(separatedBy: seMarker).first ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: b64),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let p = parse(text, fallbackName: dirName)
            if seen.insert(p.name.lowercased()).inserted { result.append(p) }
        }
        return result
    }
}
