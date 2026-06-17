import XCTest
@testable import agent_deck

final class MCPConfigWriterTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("mcp.json")
    }

    override func tearDownWithError() throws {
        if let dir = fileURL?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: dir) }
    }

    private func writeRaw(_ json: String) throws {
        try json.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func testUpsertCreatesFileWhenAbsent() throws {
        let writer = MCPConfigWriter(url: fileURL)
        var config = MCPServerConfig(); config.command = "npx"; config.args = ["-y", "pkg"]
        try writer.upsert(name: "github", config: config)

        let reloaded = writer.loadServers()
        XCTAssertEqual(reloaded["github"]?.command, "npx")
        XCTAssertEqual(reloaded["github"]?.args, ["-y", "pkg"])
    }

    func testUpsertPreservesOtherServersAndSettingsAndUnknownKeys() throws {
        try writeRaw(#"""
        {
          "settings": { "toolPrefix": "mcp" },
          "customTopLevel": { "keep": true },
          "mcpServers": {
            "existing": { "command": "keep-me", "args": ["a"] }
          }
        }
        """#)

        let writer = MCPConfigWriter(url: fileURL)
        var config = MCPServerConfig(); config.command = "node"; config.env = ["K": "V"]
        try writer.upsert(name: "added", config: config)

        // Decoded view: both servers present.
        let servers = writer.loadServers()
        XCTAssertEqual(servers["existing"]?.command, "keep-me")
        XCTAssertEqual(servers["added"]?.command, "node")

        // Raw view: settings + unknown top-level key preserved.
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        let settings = root?["settings"] as? [String: Any]
        XCTAssertEqual(settings?["toolPrefix"] as? String, "mcp")
        XCTAssertNotNil(root?["customTopLevel"])
    }

    func testEditOverwritesExistingServer() throws {
        let writer = MCPConfigWriter(url: fileURL)
        var first = MCPServerConfig(); first.command = "old"
        try writer.upsert(name: "srv", config: first)
        var second = MCPServerConfig(); second.command = "new"; second.args = ["x"]
        try writer.upsert(name: "srv", config: second)

        let servers = writer.loadServers()
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers["srv"]?.command, "new")
        XCTAssertEqual(servers["srv"]?.args, ["x"])
    }

    func testRemoveDropsOnlyTheNamedServer() throws {
        try writeRaw(#"{ "mcpServers": { "a": {"command":"a"}, "b": {"command":"b"} } }"#)
        let writer = MCPConfigWriter(url: fileURL)
        try writer.remove(name: "a")

        let servers = writer.loadServers()
        XCTAssertNil(servers["a"])
        XCTAssertEqual(servers["b"]?.command, "b")
    }

    func testRemoveMissingServerIsNoop() throws {
        try writeRaw(#"{ "mcpServers": { "a": {"command":"a"} } }"#)
        let writer = MCPConfigWriter(url: fileURL)
        try writer.remove(name: "ghost")
        XCTAssertEqual(writer.loadServers().count, 1)
    }

    func testNilFieldsAreNotSerialized() throws {
        let writer = MCPConfigWriter(url: fileURL)
        var config = MCPServerConfig(); config.command = "npx" // no args/env/url
        try writer.upsert(name: "srv", config: config)

        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        let servers = root?["mcpServers"] as? [String: Any]
        let entry = servers?["srv"] as? [String: Any]
        XCTAssertEqual(entry?["command"] as? String, "npx")
        XCTAssertNil(entry?["args"])
        XCTAssertNil(entry?["env"])
        XCTAssertNil(entry?["url"])
    }
}
