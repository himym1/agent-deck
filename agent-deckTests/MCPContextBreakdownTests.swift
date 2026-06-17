import XCTest
@testable import agent_deck

final class MCPContextBreakdownTests: XCTestCase {
    @MainActor
    func testBreakdownItemizesMCPCatalog() throws {
        // A system prompt with core instructions, a tools section, and an appended MCP catalog.
        let prompt = """
        You are a coding agent. Follow the guidelines.

        Available tools: read, grep, bash. Use them carefully.

        MCP tools (call through the `mcp` proxy tool):
        - Call a tool: mcp({ tool: "amplitude/get_context", args: { ... } })
        - Discover: mcp({}) lists servers.
        Available MCP tools:
        - amplitude/get_context: Get the current project context.
        - amplitude/query: Run an analytics query.

        Some trailing memory content here.
        """
        let estimate = try XCTUnwrap(PiAgentContextEstimateBuilder.buildPromptComposition(systemPrompt: prompt))
        let mcpRow = estimate.rows.first { $0.key == "promptMCP" }
        XCTAssertNotNil(mcpRow, "expected an MCP catalog row; got \(estimate.rows.map(\.title))")
        XCTAssertEqual(mcpRow?.title, "MCP catalog")
        XCTAssertGreaterThan(mcpRow?.tokens ?? 0, 0)
    }

    @MainActor
    func testBreakdownHasNoMCPRowWhenAbsent() throws {
        let prompt = "You are a coding agent.\n\nAvailable tools: read, grep."
        let estimate = try XCTUnwrap(PiAgentContextEstimateBuilder.buildPromptComposition(systemPrompt: prompt))
        XCTAssertNil(estimate.rows.first { $0.key == "promptMCP" })
    }
}
