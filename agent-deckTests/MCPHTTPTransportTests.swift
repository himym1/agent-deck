import XCTest
@testable import agent_deck

final class MCPHTTPTransportTests: XCTestCase {
    // MARK: - SSE parsing (unit)

    func testParseSSEExtractsDataPayloads() {
        let body = """
        event: message
        data: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}

        : a comment
        data: {"jsonrpc":"2.0","method":"notifications/x"}

        """
        let events = MCPHTTPTransport.parseSSE(body)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[0].contains("\"result\""))
        XCTAssertTrue(events[1].contains("notifications/x"))
    }

    func testParseSSEJoinsMultiLineData() {
        let body = "data: {\"a\":\ndata: 1}\n\n"
        let events = MCPHTTPTransport.parseSSE(body)
        XCTAssertEqual(events, ["{\"a\":\n1}"])
    }

    // MARK: - Real HTTP server (integration)

    private func resolveNode() -> String? {
        let candidates = [
            "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/node/bin/node").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static let serverScript = """
    const http = require('http');
    let counter = 0;
    const server = http.createServer((req, res) => {
      if (req.method === 'DELETE') { res.writeHead(200); res.end(); return; }
      if (req.method !== 'POST') { res.writeHead(405); res.end(); return; }
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        let msg; try { msg = JSON.parse(body); } catch (e) { res.writeHead(400); res.end(); return; }
        const json = (obj) => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
        if (msg.method === 'initialize') {
          res.writeHead(200, { 'Content-Type': 'application/json', 'Mcp-Session-Id': 'sess-' + (++counter) });
          res.end(JSON.stringify({ jsonrpc: '2.0', id: msg.id, result: { protocolVersion: '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'http-fixture', version: '1' } } }));
        } else if (msg.method === 'notifications/initialized') {
          res.writeHead(202); res.end();
        } else if (msg.method === 'tools/list') {
          json({ jsonrpc: '2.0', id: msg.id, result: { tools: [{ name: 'echo', description: 'Echo', inputSchema: { type: 'object' } }] } });
        } else if (msg.method === 'tools/call') {
          const a = (msg.params && msg.params.arguments) || {};
          json({ jsonrpc: '2.0', id: msg.id, result: { content: [{ type: 'text', text: 'http: ' + (a.message || '') }], isError: false } });
        } else { json({ jsonrpc: '2.0', id: msg.id, result: {} }); }
      });
    });
    server.listen(0, '127.0.0.1', () => { console.log('PORT ' + server.address().port); });
    """

    private func startFixture() throws -> (process: Process, port: Int) {
        guard let node = resolveNode() else { throw XCTSkip("node not found; skipping HTTP integration test.") }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mcp-http-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("server.js")
        try Self.serverScript.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [script.path]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        try process.run()

        let handle = outPipe.fileHandleForReading
        let semaphore = DispatchSemaphore(value: 0)
        let collected = NSMutableString()
        DispatchQueue.global().async {
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                collected.append(String(decoding: data, as: UTF8.self))
                if collected.contains("PORT ") { break }
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 20) == .success else {
            process.terminate(); throw XCTSkip("HTTP fixture did not start in time.")
        }
        guard let match = (collected as String).range(of: #"PORT (\d+)"#, options: .regularExpression),
              let port = Int((collected as String)[match].dropFirst(5)) else {
            process.terminate(); throw XCTSkip("could not read fixture port.")
        }
        return (process, port)
    }

    func testInitializeListAndCallOverRealHTTPTransport() async throws {
        let fixture = try startFixture()
        defer { fixture.process.terminate() }

        var config = MCPServerConfig()
        config.url = "http://127.0.0.1:\(fixture.port)/mcp"
        config.transport = .http
        // Default factory routes http config to the real MCPHTTPTransport.
        let connection = MCPConnection(name: "remote", config: config, requestTimeout: .seconds(15))
        defer { Task { await connection.close() } }

        let tools = try await connection.listTools()
        XCTAssertEqual(tools.map(\.name), ["echo"])

        let result = try await connection.callTool(name: "echo", arguments: .object(["message": .string("over-http")]))
        XCTAssertEqual(result.isError, false)
        XCTAssertEqual(result.combinedText, "http: over-http")
    }
}
