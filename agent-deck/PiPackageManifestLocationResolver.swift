import Foundation

nonisolated enum PiPackageManifestLocationResolver {
    static func resolve(_ entries: [String], packageDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        let includeEntries = entries.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("!") }
        let excludeEntries = entries.compactMap { entry -> String? in
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("!") else { return nil }
            return String(trimmed.dropFirst())
        }

        let excluded = Set(excludeEntries.flatMap {
            expand($0, packageDirectory: packageDirectory, fileManager: fileManager).map { $0.standardizedFileURL.path }
        })

        return includeEntries
            .flatMap { expand($0, packageDirectory: packageDirectory, fileManager: fileManager) }
            .filter { !excluded.contains($0.standardizedFileURL.path) }
    }

    private static func expand(_ entry: String, packageDirectory: URL, fileManager: FileManager) -> [URL] {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard containsGlobSyntax(trimmed) else {
            return [resolveRelativePath(trimmed, baseDirectory: packageDirectory)]
        }

        guard let regex = try? NSRegularExpression(pattern: globRegexPattern(for: normalizedPackagePattern(trimmed))) else {
            return []
        }

        var matches: [URL] = []
        guard let enumerator = fileManager.enumerator(at: packageDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        while let url = enumerator.nextObject() as? URL {
            let relative = packageRelativePath(url, packageDirectory: packageDirectory)
            let range = NSRange(relative.startIndex..<relative.endIndex, in: relative)
            if regex.firstMatch(in: relative, range: range) != nil {
                matches.append(url)
            }
        }
        return matches
    }

    private static func resolveRelativePath(_ path: String, baseDirectory: URL) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return baseDirectory.appendingPathComponent(expanded)
    }

    private static func containsGlobSyntax(_ value: String) -> Bool {
        value.contains("*") || value.contains("?")
    }

    private static func normalizedPackagePattern(_ value: String) -> String {
        var pattern = value
        while pattern.hasPrefix("./") { pattern.removeFirst(2) }
        while pattern.hasPrefix("/") { pattern.removeFirst() }
        return pattern
    }

    private static func packageRelativePath(_ url: URL, packageDirectory: URL) -> String {
        let base = packageDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(base.count + 1))
    }

    private static func globRegexPattern(for pattern: String) -> String {
        var output = "^"
        let characters = Array(pattern)
        var index = 0
        while index < characters.count {
            let char = characters[index]
            if char == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    output += ".*"
                    index += 2
                } else {
                    output += "[^/]*"
                    index += 1
                }
            } else if char == "?" {
                output += "[^/]"
                index += 1
            } else {
                output += NSRegularExpression.escapedPattern(for: String(char))
                index += 1
            }
        }
        return output + "$"
    }
}
