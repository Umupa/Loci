import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociConnect

/// Plays MCP servers and authorization servers in memory: each request goes to the handler for its method
/// and address (without the query), and is remembered.
final class FakeWeb: HTTPClient, Sendable {
  typealias Handler = @Sendable (HTTPRequest) -> HTTPResponse
  private let routes = Mutex<[String: Handler]>([:])
  private let sent = Mutex<[HTTPRequest]>([])

  var requests: [HTTPRequest] { sent.withLock { $0 } }

  func on(_ method: String, _ address: String, _ handler: @escaping Handler) {
    routes.withLock { $0["\(method) \(address)"] = handler }
  }

  func json(_ method: String, _ address: String, _ body: String, status: Int = 200, headers: [String: String] = [:]) {
    on(method, address) { _ in
      HTTPResponse(
        status: status, headers: ["Content-Type": "application/json"].merging(headers) { $1 }, body: Data(body.utf8))
    }
  }

  func send(_ request: HTTPRequest) async throws(ConnectError) -> HTTPResponse {
    sent.withLock { $0.append(request) }
    var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
    components?.query = nil
    let address = components?.url?.absoluteString ?? request.url.absoluteString
    let handler = routes.withLock { $0["\(request.method) \(address)"] }
    return handler?(request) ?? HTTPResponse(status: 404)
  }

  /// The JSON-RPC method of a request to an MCP server.
  static func method(of request: HTTPRequest) -> String? {
    request.body.flatMap { JSONValue(parsing: String(decoding: $0, as: UTF8.self)) }?["method"]?.string
  }

  static func id(of request: HTTPRequest) -> JSONValue {
    request.body.flatMap { JSONValue(parsing: String(decoding: $0, as: UTF8.self)) }?["id"] ?? .null
  }

  /// A JSON-RPC answer to `request`.
  static func answer(_ request: HTTPRequest, _ result: JSONValue, headers: [String: String] = [:]) -> HTTPResponse {
    let body = JSONValue.object(["jsonrpc": .string("2.0"), "id": id(of: request), "result": result])
    return HTTPResponse(
      status: 200, headers: ["Content-Type": "application/json"].merging(headers) { $1 }, body: Data(body.text.utf8))
  }

  /// The fields of a form post.
  static func form(_ request: HTTPRequest) -> [String: String] {
    var components = URLComponents()
    components.percentEncodedQuery = request.body.map { String(decoding: $0, as: UTF8.self) }
    return Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { first, _ in first }
  }
}

/// A notion-like server: resource metadata named in the 401, an authorization server on the same host.
enum Servers {
  static let mcp = URL(string: "https://mcp.example.com/mcp")!
  static let metadata = """
    { "issuer": "https://mcp.example.com", "authorization_endpoint": "https://mcp.example.com/authorize",
      "token_endpoint": "https://mcp.example.com/token", "registration_endpoint": "https://mcp.example.com/register",
      "code_challenge_methods_supported": ["S256"] }
    """

  static func notionLike(_ web: FakeWeb, challenge: Bool = true) {
    let header =
      challenge
      ? #"Bearer resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource/mcp", scope="read""#
      : "Bearer"
    web.json("POST", mcp.absoluteString, "{}", status: 401, headers: ["WWW-Authenticate": header])
    web.json(
      "GET", "https://mcp.example.com/.well-known/oauth-protected-resource/mcp",
      #"{ "resource": "https://mcp.example.com/mcp", "authorization_servers": ["https://mcp.example.com"], "scopes_supported": ["read", "write"] }"#
    )
    web.json("GET", "https://mcp.example.com/.well-known/oauth-authorization-server", metadata)
    web.json("POST", "https://mcp.example.com/register", #"{ "client_id": "client-1" }"#, status: 201)
  }

  static func bytes(_ count: Int) -> Data { Data(repeating: 7, count: count) }
}
