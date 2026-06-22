import XCTest
@testable import agent_deck

final class PiScannerChainWarningTests: XCTestCase {
    func testRetiredProjectChainFilesWarnAndAreNotLoadedAsAgents() throws {
        let projectURL = try PiTestSupport.temporaryProjectURL()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let chainDirectory = projectURL.appendingPathComponent(".pi/chains", isDirectory: true)
        let agentDirectory = projectURL.appendingPathComponent(".pi/agents", isDirectory: true)
        try FileManager.default.createDirectory(at: chainDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)

        let chainFile = chainDirectory.appendingPathComponent("retired.chain.md")
        let agentLikeChainFile = agentDirectory.appendingPathComponent("agent-like.chain.md")
        let chainText = """
        ---
        name: Retired Chain
        description: Retired chain file
        ---
        This should not load as an agent.
        """
        try chainText.write(to: chainFile, atomically: true, encoding: .utf8)
        try chainText.write(to: agentLikeChainFile, atomically: true, encoding: .utf8)

        let snapshot = PiScanner().scan(projectRoot: projectURL)
        let warningMessages = snapshot.warnings.map(\.message)

        XCTAssertTrue(warningMessages.contains { $0.contains("Chains are retired/unreleased") && $0.contains(chainFile.path) })
        XCTAssertTrue(warningMessages.contains { $0.contains("Chains are retired/unreleased") && $0.contains(agentLikeChainFile.path) })
        XCTAssertFalse(snapshot.projectAgents.contains { $0.filePath == agentLikeChainFile.path })
        XCTAssertFalse(snapshot.effectiveAgents.contains { $0.sourcePath == agentLikeChainFile.path })
    }
}
