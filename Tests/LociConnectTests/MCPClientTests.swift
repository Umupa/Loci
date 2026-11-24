import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociConnect

/// CN-S3: an MCP server over Streamable HTTP, answering in JSON or as an event stream.
struct MCPClientTests {
  static let tools: [JSONValue] = [
    .object([
      "name": .string("search"), "description": .string("Search pages"),
      "inputSchema": .object(["type": .string("object")]), "annotations": .object(["readOnlyHint": .bool(true)]),
    ]),
    .object(["name": .string("create_page"), "annotations": .object(["readOnlyHint": .bool(false)])]),
    .object(["name": .string("mystery")]),
  ]

  /// A server that pages its tools two and one, answers calls as an event stream, and gives a session.
  static func server(_ web: FakeWeb, forgetting: Forgetting = Forgetting()) {
    web.on("POST", Servers.mcp.absoluteString) { request in
      switch FakeWeb.method(of: request) {
      case "initialize": return FakeWeb.answer(request, .object([:]), headers: ["Mcp-Session-Id": "s-1"])
      case "notifications/initialized": return HTTPResponse(status: 202)
      case "tools/list":
        if forgetting.once() { return HTTPResponse(status: 404) }
        let cursor = request.body.flatMap { JSONValue(parsing: String(decoding: $0, as: UTF8.self)) }?["params"]?[
          "cursor"]
        return cursor == nil
          ? FakeWeb.answer(request, .object(["tools": .array(Array(tools.prefix(2))), "nextCursor": .string("p2")]))
          : FakeWeb.answer(request, .object(["tools": .array([tools[2]])]))
      default:
        let body = JSONValue.object([
          "jsonrpc": .string("2.0"), "id": FakeWeb.id(of: request),
          "result": .object([
            "content": .array([
              .object(["type": .string("text"), "text": .string("found 2 pages")]), .object(["type": .string("image")]),
            ])
          ]),
        ])
        return HTTPResponse(
          status: 200, headers: ["Content-Type": "text/event-stream"],
          body: Data("event: message\ndata: \(body.text)\n\n".utf8))
      }
    }
  }

  @Test func initializeIsFollowedByInitializedAndTheSessionIsCarried() async throws {
    let web = FakeWeb()
    Self.server(web)

    _ = try await MCPClient(server: Servers.mcp, http: web).tools(token: "t")

    #expect(
      web.requests.compactMap(FakeWeb.method) == [
        "initialize", "notifications/initialized", "tools/list", "tools/list",
      ])
    #expect(
      web.requests[2].headers["Mcp-Session-Id"] == "s-1" && web.requests[2].headers["Authorization"] == "Bearer t")
    #expect(web.requests[2].headers["MCP-Protocol-Version"] == "2025-06-18")
  }

  @Test func toolsAreListedPageByPageWithWhatTheySayAboutWriting() async throws {
    let web = FakeWeb()
    Self.server(web)

    let tools = try await MCPClient(server: Servers.mcp, http: web).tools(token: "t")

    #expect(tools.map(\.name) == ["search", "create_page", "mystery"])
    #expect(tools.map(\.readOnly) == [true, false, nil])
  }

  @Test func aReplyAsAnEventStreamGivesItsTextParts() async throws {
    let web = FakeWeb()
    Self.server(web)

    let result = try await MCPClient(server: Servers.mcp, http: web).call("search", arguments: .object([:]), token: "t")

    #expect(result == CallResult(text: "found 2 pages\n[image]", isError: false))
  }

  @Test func aLostSessionIsStartedAgainOnce() async throws {
    let web = FakeWeb()
    let forgetting = Forgetting()
    Self.server(web, forgetting: forgetting)
    let client = MCPClient(server: Servers.mcp, http: web)
    _ = try await client.call("search", arguments: .object([:]), token: "t")
    forgetting.arm()

    _ = try await client.tools(token: "t")

    #expect(web.requests.compactMap(FakeWeb.method).filter { $0 == "initialize" }.count == 2)
  }

  @Test func aServerThatWantsASignInSaysSo() async {
    let web = FakeWeb()
    web.json("POST", Servers.mcp.absoluteString, "{}", status: 401)

    await #expect(throws: ConnectError.unauthorized) {
      try await MCPClient(server: Servers.mcp, http: web).tools(token: "t")
    }
  }
}

/// Whether the server forgets its session at the next request, once.
final class Forgetting: Sendable {
  private let armed = Mutex(false)

  func arm() { armed.withLock { $0 = true } }

  func once() -> Bool {
    armed.withLock { armed in
      defer { armed = false }
      return armed
    }
  }
}
