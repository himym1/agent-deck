import Foundation

/// Reads/writes a single `mcp.json` file at the dictionary level so add/edit/remove
/// preserve the `settings` block, other servers, and any unknown keys the user wrote.
/// Agent Deck only ever writes the app-owned location (`~/.pi/agent/mcp.json`); servers
/// discovered from other files stay read-only in the UI.
nonisolated struct MCPConfigWriter {
    var url: URL

    init(url: URL = MCPConfigLoader.writableConfigURL()) {
        self.url = url
    }

    /// The current top-level JSON object, or an empty one when the file is absent/invalid.
    private func loadRoot() -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    /// The servers defined in this file only (used to decide what the UI may edit).
    func loadServers() -> [String: MCPServerConfig] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(MCPServersFile.self, from: data) else {
            return [:]
        }
        return file.mcpServers ?? [:]
    }

    func upsert(name: String, config: MCPServerConfig) throws {
        var root = loadRoot()
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[name] = try encodeConfig(config)
        root["mcpServers"] = servers
        try write(root)
    }

    func remove(name: String) throws {
        var root = loadRoot()
        guard var servers = root["mcpServers"] as? [String: Any], servers[name] != nil else { return }
        servers.removeValue(forKey: name)
        root["mcpServers"] = servers
        try write(root)
    }

    /// Encodes a config to a JSON object, dropping nil fields so the file stays minimal.
    private func encodeConfig(_ config: MCPServerConfig) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
