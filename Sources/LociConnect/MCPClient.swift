import Foundation
import LociModel

/// A tool an MCP server offers, with what it says about writing.
public struct MCPTool: Hashable, Sendable {
  public let name: String
  public let description: String
  public let inputSchema: JSONValue
  /// `annotations.readOnlyHint`; `nil` when the server does not say.
  public let readOnly: Bool?

  public init(name: String, description: String, inputSchema: JSONValue, readOnly: Bool?) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
    self.readOnly = readOnly
  }
}

/// What a tool gave back: its text parts, in order, and whether it says it failed.
public struct CallResult: Hashable, Sendable {
  public let text: String
  public let isError: Bool
}

/// One MCP server over Streamable HTTP. It initializes once and carries the session the server gives; a
/// session the server forgot is started again once. Replies come as JSON or as an event stream.
public actor MCPClient {
  nonisolated public let server: URL
  private let http: any HTTPClient
  private var session: String?
  private var initialized = false
  private var nextID = 1

  static let protocolVersion = "2025-06-18"

  public init(server: URL, http: any HTTPClient) {
    self.server = server
    self.http = http
  }

  /// Every tool, page by page.
  public func tools(token: String?) async throws(ConnectError) -> [MCPTool] {
    var tools: [MCPTool] = []
    var cursor: String?
    repeat {
      let result = try await call("tools/list", cursor.map { .object(["cursor": .string($0)]) } ?? .object([:]), token)
      for tool in result["tools"]?.array ?? [] {
        guard let name = tool["name"]?.string else { continue }
        tools.append(
          MCPTool(
            name: name, description: tool["description"]?.string ?? tool["title"]?.string ?? "",
            inputSchema: tool["inputSchema"] ?? .object([:]), readOnly: tool["annotations"]?["readOnlyHint"]?.bool))
      }
      cursor = result["nextCursor"]?.string
    } while cursor != nil
    return tools
  }

  public func call(_ tool: String, arguments: JSONValue, token: String?) async throws(ConnectError) -> CallResult {
    let result = try await call("tools/call", .object(["name": .string(tool), "arguments": arguments]), token)
    let parts = (result["content"]?.array ?? []).map { part -> String in
      switch part["type"]?.string {
      case "text": part["text"]?.string ?? ""
      case "resource": part["resource"]?["text"]?.string ?? "[resource \(part["resource"]?["uri"]?.string ?? "")]"
      case let kind?: "[\(kind)]"
      case nil: ""
      }
    }
    var text = parts.joined(separator: "\n")
    if text.isEmpty, let structured = result["structuredContent"] { text = structured.text }
    return CallResult(text: text, isError: result["isError"]?.bool ?? false)
  }

  private func call(_ method: String, _ params: JSONValue, _ token: String?) async throws(ConnectError) -> JSONValue {
    do {
      return try await once(method, params, token)
    } catch .server(let reason) where reason == Self.lostSession {
      session = nil
      initialized = false
      return try await once(method, params, token)
    }
  }

  private func once(_ method: String, _ params: JSONValue, _ token: String?) async throws(ConnectError) -> JSONValue {
    if !initialized {
      let response = try await http.send(Self.initializeRequest(to: server, token: token, session: nil))
      _ = try reply(to: response, id: 0)
      session = response.header("Mcp-Session-Id")
      let notice = JSONValue.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")])
      _ = try await http.send(request(notice, token: token))
      initialized = true
    }
    nextID += 1
    let id = nextID
    let body = JSONValue.object([
      "jsonrpc": .string("2.0"), "id": .integer(Int64(id)), "method": .string(method), "params": params,
    ])
    let response = try await http.send(request(body, token: token))
    if response.status == 404, session != nil { throw .server(Self.lostSession) }
    return try reply(to: response, id: id)
  }

  static let lostSession = "the server forgot the session"

  private func request(_ body: JSONValue, token: String?) -> HTTPRequest {
    var headers = Self.headers(token: token)
    headers["MCP-Protocol-Version"] = Self.protocolVersion
    if let session { headers["Mcp-Session-Id"] = session }
    return HTTPRequest("POST", server, headers: headers, body: Data(body.text.utf8))
  }

  static func initializeRequest(to server: URL, token: String?, session: String?) -> HTTPRequest {
    let body = JSONValue.object([
      "jsonrpc": .string("2.0"), "id": .integer(0), "method": .string("initialize"),
      "params": .object([
        "protocolVersion": .string(protocolVersion), "capabilities": .object([:]),
        "clientInfo": .object(["name": .string("Loci"), "version": .string("1")]),
      ]),
    ])
    return HTTPRequest("POST", server, headers: headers(token: token), body: Data(body.text.utf8))
  }

  private static func headers(token: String?) -> [String: String] {
    var headers = ["Content-Type": "application/json", "Accept": "application/json, text/event-stream"]
    if let token { headers["Authorization"] = "Bearer \(token)" }
    return headers
  }

  /// The result of the JSON-RPC reply with `id`, from a JSON body or from an event stream.
  private func reply(to response: HTTPResponse, id: Int) throws(ConnectError) -> JSONValue {
    if response.status == 401 { throw .unauthorized }
    guard (200..<300).contains(response.status) else { throw .server("the server answered HTTP \(response.status)") }
    let messages: [JSONValue]
    if response.header("Content-Type")?.contains("text/event-stream") == true {
      messages = String(decoding: response.body, as: UTF8.self).split(separator: "\n")
        .filter { $0.hasPrefix("data:") }
        .compactMap { JSONValue(parsing: String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
    } else {
      messages = response.json.map { $0.array ?? [$0] } ?? []
    }
    guard let message = messages.first(where: { $0["id"]?.number == Double(id) }) else {
      throw .server("the server gave no answer to the request")
    }
    if let error = message["error"] {
      throw .server(error["message"]?.string ?? "the server refused the request")
    }
    return message["result"] ?? .object([:])
  }
}
