import Foundation

/// Parsing of the leading `--- … ---` YAML-ish frontmatter block of a `SKILL.md`.
///
/// Shared by `ExternalSkillDiscovery` (which reads the head of an on-disk file)
/// and `SkillRepositorySyncService` (which parses the output of `git show`).
/// Pure, `nonisolated`, no main-actor coupling.
nonisolated enum SkillFrontmatter {

    /// Parse a leading `--- … ---` frontmatter block into key/value pairs.
    /// Returns an empty dictionary when no frontmatter block is present.
    ///
    /// Handles YAML block scalars (``>`` folded, ``|`` literal) so that
    /// multi-line ``description`` fields and similar keys capture their full
    /// indented continuation text instead of just the indicator character.
    static func parse(_ text: String) -> [String: String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { return [:] }
        let remainder = String(normalized.dropFirst(4))
        guard let closingRange = remainder.range(of: "\n---\n")
            ?? (remainder.hasSuffix("\n---") ? remainder.range(of: "\n---", options: .backwards) : nil)
        else { return [:] }
        let frontmatterText = String(remainder[..<closingRange.lowerBound])
        let rawLines = frontmatterText.components(separatedBy: "\n")

        var values: [String: String] = [:]
        var i = 0
        while i < rawLines.count {
            let rawLine = rawLines[i]
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: ":") else {
                i += 1
                continue
            }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty else { i += 1; continue }

            if isBlockScalarIndicator(value) {
                // Consume subsequent indented lines as the block-scalar value.
                i += 1
                let keyLineIndent = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                var blockLines: [String] = []
                while i < rawLines.count {
                    let nextRaw = rawLines[i]
                    let nextTrimmed = nextRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Empty lines and comment lines inside a block scalar are
                    // part of it (YAML treats blank lines as line breaks).
                    if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("#") {
                        blockLines.append(nextTrimmed)
                        i += 1
                        continue
                    }
                    let nextIndent = nextRaw.prefix(while: { $0 == " " || $0 == "\t" }).count
                    if nextIndent > keyLineIndent {
                        blockLines.append(nextTrimmed)
                        i += 1
                    } else {
                        break
                    }
                }
                let joined: String
                if value.hasPrefix("|") {
                    // Literal scalar — preserve newlines.
                    joined = blockLines.joined(separator: "\n")
                } else {
                    // Folded scalar — newlines become spaces.
                    joined = blockLines
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }
                if !joined.isEmpty {
                    values[String(key)] = joined
                }
            } else {
                values[String(key)] = String(value)
                i += 1
            }
        }
        return values
    }

    /// Returns `true` when *value* is a YAML block-scalar indicator: ``>``
    /// (folded), ``|`` (literal), and their common variants with chomping
    /// (``-`` strip, ``+`` keep) or explicit indentation (e.g. ``>2``).
    static func isBlockScalarIndicator(_ value: String) -> Bool {
        guard let first = value.first, first == ">" || first == "|" else { return false }
        let rest = value.dropFirst()
        return rest.allSatisfy { $0 == "-" || $0 == "+" || ($0 >= "0" && $0 <= "9") }
    }

    /// Read only the head of `url` and parse its frontmatter block. Returns
    /// `nil` when the file cannot be read (e.g. it does not exist).
    ///
    /// Frontmatter always sits at the very top of the file, so a bounded read
    /// avoids pulling large skill bodies into memory just for two fields.
    static func fields(atTopOf url: URL, byteLimit: Int = 64 * 1024) -> [String: String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: byteLimit)) ?? Data()
        guard let text = decodeUTF8Prefix(data) else { return nil }
        return parse(text)
    }

    /// Decode a possibly-truncated UTF-8 byte prefix. A bounded read can slice
    /// through a multi-byte character; dropping up to three trailing bytes
    /// recovers a valid string (a UTF-8 scalar is at most four bytes).
    static func decodeUTF8Prefix(_ data: Data) -> String? {
        for trailingBytesToDrop in 0...min(3, data.count) {
            if let text = String(data: data.dropLast(trailingBytesToDrop), encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    /// Resolve a skill's display name and description from parsed frontmatter,
    /// falling back to the skill folder name when `name` is absent.
    static func nameAndDescription(
        fromFrontmatter frontmatter: [String: String],
        fallbackName: String
    ) -> (name: String, description: String?) {
        let parsedName = frontmatter["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedDescription = frontmatter["description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (parsedName?.isEmpty == false) ? parsedName! : fallbackName
        let description = (parsedDescription?.isEmpty == false) ? parsedDescription : nil
        return (name, description)
    }
}
