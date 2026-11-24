import Foundation
import LociModel

/// One HTTP request a connector makes: to an MCP server, or to an authorization server.
public struct HTTPRequest: Hashable, Sendable {
  public var method: String
  public var url: URL
  public var headers: [String: String]
  public var body: Data?

  public init(_ method: String, _ url: URL, headers: [String: String] = [:], body: Data? = nil) {
    self.method = method
    self.url = url
    self.headers = headers
    self.body = body
  }

  /// A form post, as token endpoints take.
  static func form(_ url: URL, _ fields: [String: String]) -> HTTPRequest {
    var components = URLComponents()
    components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    let body = (components.percentEncodedQuery ?? "").replacing("+", with: "%2B")
    return HTTPRequest(
      "POST", url,
      headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
      body: Data(body.utf8))
  }
}

public struct HTTPResponse: Hashable, Sendable {
  public let status: Int
  /// Header names in lowercase.
  public let headers: [String: String]
  public let body: Data

  public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
    self.status = status
    self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
    self.body = body
  }

  public func header(_ name: String) -> String? { headers[name.lowercased()] }

  var json: JSONValue? { try? JSONDecoder().decode(JSONValue.self, from: body) }
}

/// Where connectors' requests go; tests give one that plays the servers.
public protocol HTTPClient: Sendable {
  func send(_ request: HTTPRequest) async throws(ConnectError) -> HTTPResponse
}

/// The network. Redirects are not followed: an authorization server's redirect is an answer, not a detour.
public struct URLSessionClient: HTTPClient {
  private let session: URLSession

  public init(timeout: Duration = .seconds(30)) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = Double(timeout.components.seconds)
    session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
  }

  public func send(_ request: HTTPRequest) async throws(ConnectError) -> HTTPResponse {
    var sent = URLRequest(url: request.url)
    sent.httpMethod = request.method
    sent.httpBody = request.body
    for (name, value) in request.headers { sent.setValue(value, forHTTPHeaderField: name) }
    do {
      let (data, response) = try await session.data(for: sent)
      guard let http = response as? HTTPURLResponse else { throw ConnectError.server("not an HTTP response") }
      let headers = http.allHeaderFields.reduce(into: [String: String]()) { headers, field in
        if let name = field.key as? String, let value = field.value as? String { headers[name] = value }
      }
      return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    } catch let error as ConnectError {
      throw error
    } catch {
      throw .offline(error.localizedDescription)
    }
  }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
