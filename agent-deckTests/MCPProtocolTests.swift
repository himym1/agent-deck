import XCTest
@testable import agent_deck

final class MCPProtocolTests: XCTestCase {
    func testEncodeInitializeLine() throws {
        let request = MCPRequestFactory.initialize(id: 1, clientName: "Agent Deck", clientVersion: "1.0")
        let line = try MCPRequestFactory.encodeLine(request)
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertTrue(line.contains("\"jsonrpc\":\"2.0\""))
        XCTAssertTrue(line.contains("\"method\":\"initialize\""))
        XCTAssertTrue(line.contains("\"id\":1"))
        XCTAssertTrue(line.contains("\"protocolVersion\":\"\(MCPProtocolVersion.preferred)\""))
        XCTAssertTrue(line.contains("\"name\":\"Agent Deck\""))
    }

    func testInitializedIsNotificationWithoutId() throws {
        let line = try MCPRequestFactory.encodeLine(MCPRequestFactory.initialized())
        XCTAssertFalse(line.contains("\"id\""))
        XCTAssertTrue(line.contains("\"method\":\"notifications/initialized\""))
    }

    func testToolsListCursorOmittedWhenNil() throws {
        let none = try MCPRequestFactory.encodeLine(MCPRequestFactory.toolsList(id: 2, cursor: nil))
        XCTAssertFalse(none.contains("cursor"))
        let withCursor = try MCPRequestFactory.encodeLine(MCPRequestFactory.toolsList(id: 3, cursor: "abc"))
        XCTAssertTrue(withCursor.contains("\"cursor\":\"abc\""))
    }

    func testToolsCallEncodesNameAndArguments() throws {
        let args: JSONValue = .object(["path": .string("/tmp"), "limit": .number(5)])
        let line = try MCPRequestFactory.encodeLine(MCPRequestFactory.toolsCall(id: 4, name: "read", arguments: args))
        XCTAssertTrue(line.contains("\"name\":\"read\""))
        XCTAssertTrue(line.contains("\"path\":\"/tmp\""))
    }

    func testDecodeToolsListResultWithPaginationCursor() throws {
        let json = """
        {"jsonrpc":"2.0","id":2,"result":{"tools":[
            {"name":"echo","description":"Echo input","inputSchema":{"type":"object"}},
            {"name":"add"}
        ],"nextCursor":"page2"}}
        """
        let response = try MCPRequestFactory.decode(json)
        XCTAssertEqual(response.id, .int(2))
        XCTAssertNil(response.error)
        let result = try XCTUnwrap(response.result)
        let decoded = try JSONDecoder().decode(MCPToolsListResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.tools.count, 2)
        XCTAssertEqual(decoded.tools.first?.name, "echo")
        XCTAssertEqual(decoded.tools.first?.description, "Echo input")
        XCTAssertNil(decoded.tools.last?.description)
        XCTAssertEqual(decoded.nextCursor, "page2")
    }

    func testDecodeToolsCallResultCombinesTextAndMarksNonText() throws {
        let json = """
        {"jsonrpc":"2.0","id":7,"result":{"content":[
            {"type":"text","text":"hello"},
            {"type":"image","data":"…"},
            {"type":"text","text":"world"}
        ],"isError":false}}
        """
        let response = try MCPRequestFactory.decode(json)
        let result = try JSONDecoder().decode(MCPCallResult.self, from: JSONEncoder().encode(try XCTUnwrap(response.result)))
        XCTAssertEqual(result.isError, false)
        XCTAssertEqual(result.combinedText, "hello\n[image content]\nworld")
    }

    func testDecodeErrorResponse() throws {
        let json = """
        {"jsonrpc":"2.0","id":9,"error":{"code":-32601,"message":"Method not found"}}
        """
        let response = try MCPRequestFactory.decode(json)
        XCTAssertEqual(response.error?.code, -32601)
        XCTAssertEqual(response.error?.message, "Method not found")
        XCTAssertNil(response.result)
    }

    func testDecodeNotificationHasNoId() throws {
        let json = """
        {"jsonrpc":"2.0","method":"notifications/tools/list_changed"}
        """
        let response = try MCPRequestFactory.decode(json)
        XCTAssertTrue(response.isNotification)
        XCTAssertEqual(response.method, "notifications/tools/list_changed")
        XCTAssertNil(response.id)
    }
}
