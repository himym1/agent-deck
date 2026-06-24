import XCTest
@testable import agent_deck

final class MCPConfigParserTests: XCTestCase {
    // MARK: - JSON

    func testParsesMcpServersJSONWithStreamableHttpAlias() {
        let json = #"""
        { "mcpServers": { "Amplitude": { "url": "https://mcp.amplitude.com/mcp", "transport": "streamable-http" } } }
        """#
        let parsed = MCPConfigParser.parse(json)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.name, "Amplitude")
        XCTAssertEqual(parsed.first?.config.url, "https://mcp.amplitude.com/mcp")
        XCTAssertEqual(parsed.first?.config.transport, .http) // streamable-http normalizes to http
    }

    func testParsesStdioJSON() {
        let json = #"""
        { "mcpServers": { "github": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"], "env": { "GITHUB_TOKEN": "x" } } } }
        """#
        let parsed = MCPConfigParser.parse(json)
        XCTAssertEqual(parsed.first?.name, "github")
        XCTAssertEqual(parsed.first?.config.command, "npx")
        XCTAssertEqual(parsed.first?.config.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(parsed.first?.config.env?["GITHUB_TOKEN"], "x")
        XCTAssertEqual(parsed.first?.config.resolvedTransport, .stdio)
    }

    func testParsesBareSingleServerObject() {
        let parsed = MCPConfigParser.parse(#"{ "url": "https://mcp.amplitude.com/mcp", "transport": "streamable-http" }"#)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertNil(parsed.first?.name) // no name in a bare object — UI asks for it
        XCTAssertEqual(parsed.first?.config.url, "https://mcp.amplitude.com/mcp")
    }

    func testParsesMultipleServers() {
        let json = #"""
        { "mcpServers": { "a": {"command":"x"}, "b": {"url":"https://b/mcp"} } }
        """#
        let parsed = MCPConfigParser.parse(json)
        XCTAssertEqual(parsed.map(\.name), ["a", "b"])
    }

    // MARK: - claude mcp add

    func testParsesClaudeHttpAddCommand() {
        let parsed = MCPConfigParser.parse(#"claude mcp add -t http -s user Amplitude "https://mcp.amplitude.com/mcp""#)
        XCTAssertEqual(parsed.first?.name, "Amplitude")
        XCTAssertEqual(parsed.first?.config.url, "https://mcp.amplitude.com/mcp")
        XCTAssertEqual(parsed.first?.config.transport, .http)
    }

    func testParsesClaudeStdioAddCommandWithDashDash() {
        let parsed = MCPConfigParser.parse("claude mcp add github -- npx -y @modelcontextprotocol/server-github")
        XCTAssertEqual(parsed.first?.name, "github")
        XCTAssertEqual(parsed.first?.config.command, "npx")
        XCTAssertEqual(parsed.first?.config.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(parsed.first?.config.transport, .stdio)
    }

    // MARK: - codex mcp add

    func testParsesCodexUrlAddCommand() {
        let parsed = MCPConfigParser.parse("codex mcp add amplitude --url https://mcp.amplitude.com/mcp")
        XCTAssertEqual(parsed.first?.name, "amplitude")
        XCTAssertEqual(parsed.first?.config.url, "https://mcp.amplitude.com/mcp")
        XCTAssertEqual(parsed.first?.config.transport, .http)
    }

    func testParsesCodexStdioAddCommand() {
        let parsed = MCPConfigParser.parse("codex mcp add fs -- npx -y @modelcontextprotocol/server-filesystem /tmp")
        XCTAssertEqual(parsed.first?.name, "fs")
        XCTAssertEqual(parsed.first?.config.command, "npx")
        XCTAssertEqual(parsed.first?.config.args, ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
    }

    // MARK: - Robustness

    func testEmptyAndGarbageYieldNothing() {
        XCTAssertTrue(MCPConfigParser.parse("").isEmpty)
        XCTAssertTrue(MCPConfigParser.parse("hello world").isEmpty)
        XCTAssertTrue(MCPConfigParser.parse("npm install foo").isEmpty)
    }

    func testTokenizerHonorsQuotes() {
        XCTAssertEqual(MCPConfigParser.shellTokenize(#"a "b c" 'd e' f"#), ["a", "b c", "d e", "f"])
    }
}
