import Foundation
import Synchronization

/// An HTTP server inside the process, reached through `URLProtocol`: each host answers from its own script,
/// and every request it gets is remembered.
final class ScriptedServer: URLProtocol {
  /// One reply: a status, headers, the body in chunks, and whether the connection drops after them.
  struct Reply: Sendable {
    let status: Int
    let headers: [String: String]
    let chunks: [Data]
    let drops: Bool

    init(status: Int = 200, headers: [String: String] = [:], chunks: [Data], drops: Bool = false) {
      self.status = status
      self.headers = headers
      self.chunks = chunks
      self.drops = drops
    }
  }

  private static let scripts = Mutex<[String: [Reply]]>([:])
  private static let received = Mutex<[String: [URLRequest]]>([:])

  /// A new host whose requests get `replies` in turn, the last one again once the others are used.
  static func host(answering replies: [Reply]) -> URL {
    let host = "server-\(UUID().uuidString.lowercased()).test"
    scripts.withLock { $0[host] = replies }
    return URL(string: "https://\(host)/Loci.dmg")!
  }

  static func requests(to address: URL) -> [URLRequest] {
    received.withLock { $0[address.host() ?? ""] ?? [] }
  }

  static func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScriptedServer.self]
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let host = request.url?.host() ?? ""
    let request = request
    let reply: Reply? = Self.scripts.withLock { scripts in
      guard let replies = scripts[host], let first = replies.first else { return nil }
      if replies.count > 1 { scripts[host] = Array(replies.dropFirst()) }
      return first
    }
    Self.received.withLock { $0[host, default: []].append(request) }
    guard let reply, let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else { return client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost)) ?? () }
    let client = client
    let loading = Loading(self)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    Task {
      for chunk in reply.chunks {
        try? await Task.sleep(for: .milliseconds(20))
        client?.urlProtocol(loading.protocol, didLoad: chunk)
      }
      try? await Task.sleep(for: .milliseconds(20))
      if reply.drops {
        client?.urlProtocol(loading.protocol, didFailWithError: URLError(.networkConnectionLost))
      } else {
        client?.urlProtocolDidFinishLoading(loading.protocol)
      }
    }
  }

  override func stopLoading() {}
}

/// The loading protocol handed to the task that sends the body in pieces.
private struct Loading: @unchecked Sendable {
  let `protocol`: URLProtocol

  init(_ loading: URLProtocol) {
    `protocol` = loading
  }
}
