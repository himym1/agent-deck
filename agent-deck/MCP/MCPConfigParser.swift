import Foundation

/// One server parsed from pasted text. `name` is nil when the source didn't carry
/// one (a bare server object) so the UI can ask for it.
nonisolated struct MCPParsedServer: Equatable, Sendable {
    var name: String?
    var config: MCPServerConfig
}

/// Parses whatever a user copies from a server's docs into server configs. Accepts:
///  - a raw `mcp.json` block (`{ "mcpServers": { … } }`), a bare `{ name: { … } }`
///    map, or a single server object;
///  - `claude mcp add [-t http] [-s user] <name> <url|command> [args…]`;
///  - `codex mcp add <name> [--url <url>] [-- <command> args…]`.
/// Returns [] when nothing parses.
nonisolated enum MCPConfigParser {
    static func parse(_ text: String) -> [MCPParsedServer] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return parseJSON(trimmed)
        }
        return parseCLI(trimmed)
    }

    // MARK: - JSON

    private static func parseJSON(_ text: String) -> [MCPParsedServer] {
        guard let data = text.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()

        // 1. Full file shape: { "mcpServers": { name: config } }
        if let file = try? decoder.decode(MCPServersFile.self, from: data),
           let servers = file.mcpServers, !servers.isEmpty {
            return servers
                .map { MCPParsedServer(name: $0.key, config: $0.value) }
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
        }

        // 2. A bare { name: config, … } map (no mcpServers wrapper).
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var parsed: [MCPParsedServer] = []
            for (key, value) in object {
                guard let valueObject = value as? [String: Any],
                      let valueData = try? JSONSerialization.data(withJSONObject: valueObject),
                      let config = try? decoder.decode(MCPServerConfig.self, from: valueData),
                      config.command != nil || config.url != nil else { continue }
                parsed.append(MCPParsedServer(name: key, config: config))
            }
            if !parsed.isEmpty {
                return parsed.sorted { ($0.name ?? "") < ($1.name ?? "") }
            }

            // 3. A single server object: { "url": … } or { "command": … }.
            if let config = try? decoder.decode(MCPServerConfig.self, from: data),
               config.command != nil || config.url != nil {
                return [MCPParsedServer(name: object["name"] as? String, config: config)]
            }
        }
        return []
    }

    // MARK: - CLI

    private static func parseCLI(_ text: String) -> [MCPParsedServer] {
        let tokens = shellTokenize(text)
        // Expect "<tool> mcp add …" (claude / codex / others).
        guard tokens.count >= 4, tokens[1] == "mcp", tokens[2] == "add" else { return [] }
        let rest = Array(tokens.dropFirst(3))

        var transport: MCPTransportKind?
        var url: String?
        var env: [String: String] = [:]
        var headers: [String: String] = [:]
        var positionals: [String] = []
        var commandArgs: [String] = []
        var afterDashDash = false

        var index = 0
        while index < rest.count {
            let token = rest[index]
            if afterDashDash { commandArgs.append(token); index += 1; continue }
            switch token {
            case "--":
                afterDashDash = true; index += 1
            case "-t", "--transport", "--type":
                if index + 1 < rest.count { transport = MCPTransportKind.normalized(rest[index + 1]); index += 2 } else { index += 1 }
            case "--url":
                if index + 1 < rest.count { url = rest[index + 1]; index += 2 } else { index += 1 }
            case "-s", "--scope":
                index += (index + 1 < rest.count ? 2 : 1) // scope is host-specific; ignore
            case "-e", "--env":
                if index + 1 < rest.count { addPair(rest[index + 1], into: &env); index += 2 } else { index += 1 }
            case "-H", "--header":
                if index + 1 < rest.count { addPair(rest[index + 1], into: &headers, separator: ":"); index += 2 } else { index += 1 }
            default:
                if token.hasPrefix("--") && token.contains("=") {
                    // --url=… style
                    let parts = token.dropFirst(2).split(separator: "=", maxSplits: 1)
                    if parts.first == "url", parts.count == 2 { url = String(parts[1]) }
                    index += 1
                } else if token.hasPrefix("-") {
                    index += 1 // unknown flag
                } else {
                    positionals.append(token); index += 1
                }
            }
        }

        guard let name = positionals.first else { return [] }
        let remaining = Array(positionals.dropFirst())
        let urlCandidate = url ?? remaining.first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }

        var config = MCPServerConfig()
        let isRemote = urlCandidate != nil && transport != .stdio
        if isRemote, let urlCandidate {
            config.url = urlCandidate
            config.transport = transport ?? .http
            if !headers.isEmpty { config.headers = headers }
        } else {
            let commandTokens = commandArgs.isEmpty ? remaining : commandArgs
            guard let command = commandTokens.first else { return [] }
            config.command = command
            let args = Array(commandTokens.dropFirst())
            config.args = args.isEmpty ? nil : args
            config.transport = .stdio
            if !env.isEmpty { config.env = env }
        }
        return [MCPParsedServer(name: name, config: config)]
    }

    private static func addPair(_ raw: String, into dict: inout [String: String], separator: Character = "=") {
        let parts = raw.split(separator: separator, maxSplits: 1)
        guard parts.count == 2 else { return }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { dict[key] = parts[1].trimmingCharacters(in: .whitespaces) }
    }

    /// Minimal shell-style tokenizer honoring single/double quotes (no escape handling
    /// beyond stripping the quotes — enough for pasted `mcp add` commands).
    static func shellTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        for character in text {
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character; hasToken = true
            } else if character.isWhitespace {
                if hasToken { tokens.append(current); current = ""; hasToken = false }
            } else {
                current.append(character); hasToken = true
            }
        }
        if hasToken { tokens.append(current) }
        return tokens
    }
}
