import XCTest
@testable import agent_deck

final class MCPBridgeAndConflictTests: XCTestCase {
    @MainActor
    func testMCPBridgeSourceRegistersProxyToolAndRoundTrips() throws {
        let source = try String(contentsOf: PiNativeSubagentBridgeExtensions.mcpExtensionURL(), encoding: .utf8)
        XCTAssertTrue(source.contains(#"name: "mcp""#))
        XCTAssertTrue(source.contains("AGENT_DECK_BRIDGE mcp"))
        XCTAssertTrue(source.contains(#"bridge: "agent_deck_mcp""#))
        // The four proxy actions the model can drive.
        for key in ["search", "describe", "tool", "args"] {
            XCTAssertTrue(source.contains(key), "bridge source should reference \(key)")
        }
        for action in ["\"list\"", "\"search\"", "\"describe\"", "\"call\""] {
            XCTAssertTrue(source.contains(action), "bridge source should set action \(action)")
        }
    }

    func testMCPProxyToolNameIsInAllBridgeToolNames() {
        XCTAssertTrue(PiNativeSubagentBridgeExtensions.allBridgeToolNames.contains("mcp"))
        XCTAssertEqual(PiNativeSubagentBridgeExtensions.mcpProxyToolName, "mcp")
    }

    /// A delegated/bound agent with a restrictive `tools:` allowlist must get `mcp`
    /// added to it when the bridge is injected, or Pi blocks the bridge-registered
    /// tool (mirrors how memory tools are auto-included).
    @MainActor
    func testRestrictiveAllowlistIncludesMCPToolWhenInjected() {
        let agent = PiTestSupport.makeAgent(name: "reviewer", tools: ["read", "edit"])
        let withMCP = PiAgentLaunchArgumentBuilder.toolArguments(.init(
            agent: agent, includeSupervisorTool: false, includeMemoryTools: false,
            includeExaTools: false, includeFallbackWebFetchTool: false, includeMCPTool: true
        ))
        XCTAssertEqual(withMCP.first, "--tools")
        XCTAssertTrue((withMCP.last ?? "").split(separator: ",").map(String.init).contains("mcp"),
                      "mcp must be in the allowlist when injected; got \(withMCP)")

        let withoutMCP = PiAgentLaunchArgumentBuilder.toolArguments(.init(
            agent: agent, includeSupervisorTool: false, includeMemoryTools: false,
            includeExaTools: false, includeFallbackWebFetchTool: false, includeMCPTool: false
        ))
        XCTAssertFalse((withoutMCP.last ?? "").split(separator: ",").map(String.init).contains("mcp"))
    }

    /// An agent with NO `tools:` field is unrestricted (Pi defaults), so no `--tools`
    /// is emitted and `mcp` is available without being listed.
    @MainActor
    func testUnrestrictedAgentEmitsNoToolsFlagEvenWithMCP() {
        let agent = PiTestSupport.makeAgent(name: "free", tools: nil)
        let args = PiAgentLaunchArgumentBuilder.toolArguments(.init(
            agent: agent, includeSupervisorTool: false, includeMemoryTools: false,
            includeExaTools: false, includeFallbackWebFetchTool: false, includeMCPTool: true
        ))
        XCTAssertTrue(args.isEmpty, "no allowlist → no --tools restriction; got \(args)")
    }

    func testBridgeDescriptorsIncludeMCP() {
        XCTAssertTrue(PiNativeSubagentBridgeExtensions.bridgeDescriptors.contains { $0.id == "mcp" })
    }

    func testInjectedParentBridgesIncludesMCPWhenActive() {
        let active = PiNativeSubagentBridgeExtensions.injectedParentBridges(
            memoryEnabled: false, exaConfigured: false, fallbackWebFetchAvailable: false,
            subagentsActive: false, mcpActive: true
        )
        XCTAssertTrue(active.contains { $0.id == "mcp" })

        let inactive = PiNativeSubagentBridgeExtensions.injectedParentBridges(
            memoryEnabled: false, exaConfigured: false, fallbackWebFetchAvailable: false,
            subagentsActive: false, mcpActive: false
        )
        XCTAssertFalse(inactive.contains { $0.id == "mcp" })
    }

    // MARK: - Collision detection

    private func makeCandidate(source: String) throws -> PiExtensionCandidate {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-conflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("index.ts")
        try source.write(to: file, atomically: true, encoding: .utf8)
        return PiExtensionCandidate(
            id: file.path,
            name: "test-ext",
            launchSource: file.path,
            source: ScopeID(kind: .global, path: dir.path),
            discoveryKind: .autoDirectory,
            packageName: nil
        )
    }

    func testDetectsExtensionRegisteringLiteralMcpTool() throws {
        let candidate = try makeCandidate(source: #"pi.registerTool({ name: "mcp", description: "x" })"#)
        XCTAssertTrue(PiExtensionConflictDetector.conflictingBridgeToolNames(for: candidate).contains("mcp"))
    }

    func testDetectsAdapterPrefixedToolsAndCommand() throws {
        let prefixed = try makeCandidate(source: #"registerTool({ name: "mcp_github_search_issues" })"#)
        XCTAssertTrue(PiExtensionConflictDetector.conflictingBridgeToolNames(for: prefixed).contains("mcp"))

        let command = try makeCandidate(source: #"pi.registerCommand("/mcp", { handler })"#)
        XCTAssertTrue(PiExtensionConflictDetector.conflictingBridgeToolNames(for: command).contains("mcp"))
    }

    func testUnrelatedExtensionHasNoMCPConflict() throws {
        let candidate = try makeCandidate(source: #"pi.registerTool({ name: "weather_lookup" })"#)
        XCTAssertFalse(PiExtensionConflictDetector.conflictingBridgeToolNames(for: candidate).contains("mcp"))
    }
}
