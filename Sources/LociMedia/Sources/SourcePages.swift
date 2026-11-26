import Foundation
import LociModel

/// Sends one request and gives back its answer as it is, never following a redirect and never refusing a
/// status: the caller decides each hop.
public protocol PageHops: Sendable {
  func send(_ request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse)
}

/// Reads a page for a data source, on a line of its own: the app sends every request itself, each a GET,
/// following each redirect only after looking at where it goes, and the sign-in goes only to the site it is
/// for. Only the answer that passed this reaches the page reader, which parses it as a document that loads
/// nothing and runs none of its scripts, so a page can send nothing of its own: no subresource, fetch,
/// XMLHttpRequest, WebSocket or worker.
public struct SourcePages: Sendable {
  let hops: any PageHops
  /// The most redirects followed for one page.
  public static let mostHops = 5
  public static let mostBytes = 2_000_000
  static let timeout: TimeInterval = 10

  public init(hops: any PageHops) {
    self.hops = hops
  }

  /// The page's text. `cookies` are sent only to a hop on one of `domains`, the signed-in site's.
  public func read(_ url: URL, cookies: [HTTPCookie] = [], domains: [String] = []) async throws(FetchError)
    -> String
  {
    var address = url
    for _ in 0...Self.mostHops {
      guard address.isWebLink else { throw FetchError(reason: "\(address.absoluteString) is not an http(s) link") }
      let (data, response) = try await hops.send(Self.request(address, cookies: cookies, domains: domains))
      if (300..<400).contains(response.statusCode) {
        guard let location = response.value(forHTTPHeaderField: "Location"),
          let next = URL(string: location, relativeTo: address)?.absoluteURL
        else { throw FetchError(reason: "\(address.absoluteString) redirects nowhere (HTTP \(response.statusCode))") }
        address = next
        continue
      }
      if let failure = PageReader.failure(status: response.statusCode) { throw failure }
      guard data.count <= Self.mostBytes else {
        throw FetchError(reason: "the page is larger than \(Self.mostBytes / 1_000_000) MB")
      }
      let text = String(decoding: data, as: UTF8.self)
      guard response.mimeType?.lowercased().contains("html") ?? true else { return text }
      return try await Self.text(of: text, at: address)
    }
    throw FetchError(reason: "\(url.absoluteString) redirects more than \(Self.mostHops) times")
  }

  /// A GET that carries no cookie of the system's, only the site's own, and only to that site.
  static func request(_ url: URL, cookies: [HTTPCookie], domains: [String]) -> URLRequest {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.httpMethod = "GET"
    request.httpShouldHandleCookies = false
    request.setValue(SourceFetcher.userAgent, forHTTPHeaderField: "User-Agent")
    let host = url.host()?.lowercased() ?? ""
    let onSite = domains.contains { host == $0 || host.hasSuffix("." + $0) }
    let sent = onSite ? cookies.filter { Self.cookie($0, goesTo: url) } : []
    for (field, value) in HTTPCookie.requestHeaderFields(with: sent) {
      request.setValue(value, forHTTPHeaderField: field)
    }
    return request
  }

  private static func cookie(_ cookie: HTTPCookie, goesTo url: URL) -> Bool {
    let host = url.host()?.lowercased() ?? ""
    let domain = cookie.domain.lowercased()
    let own = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    guard host == own || (domain.hasPrefix(".") && host.hasSuffix(domain)) else { return false }
    guard !cookie.isSecure || url.scheme == "https" else { return false }
    return url.path().isEmpty ? cookie.path == "/" : url.path().hasPrefix(cookie.path)
  }

  @MainActor
  private static func text(of html: String, at address: URL) async throws(FetchError) -> String {
    let page = try await PageReader.inert(html, base: address)
    guard !page.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw FetchError(reason: "The page has no readable text.")
    }
    return page.markdown
  }
}

/// Requests over the network as no one: no cookies, cache or credentials of the system's, and no redirect
/// followed on its own.
public struct HopNetwork: PageHops {
  private let session: URLSession

  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    session = URLSession(configuration: configuration, delegate: StopAtRedirects(), delegateQueue: nil)
  }

  public func send(_ request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw FetchError(
        reason: (error as? URLError)?.localizedDescription ?? error.localizedDescription, cause: .network)
    }
    guard let response = response as? HTTPURLResponse else { throw FetchError(reason: "not an HTTP response") }
    return (data, response)
  }
}

private final class StopAtRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
