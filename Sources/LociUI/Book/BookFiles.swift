import Foundation
import LociModel
import WebKit

/// Serves a book's files to its page from the host, under `loci-book://book/<path>`. Files already asked for
/// are kept for a while, and the next chapter and what it uses are fetched ahead, so turning into it waits for
/// no other Mac.
@MainActor
final class BookFiles: NSObject, WKURLSchemeHandler {
  static let scheme = "loci-book"
  /// A chapter asked for with this query is served as HTML, for a page that is not well-formed XHTML.
  static let asHTML = "html"
  static let budget = 48 * 1024 * 1024

  private let item: EntityID
  private let read: @MainActor (String) async throws -> Data
  private var kept: [String: Data] = [:]
  private var order: [String] = []
  private var fetching: [String: Task<Data, any Error>] = [:]
  private var running: Set<ObjectIdentifier> = []

  init(item: EntityID, host: any LociModel.Host) {
    self.item = item
    read = { path in try await host.run(ReadBookFile(item: item, path: path)) }
  }

  init(item: EntityID, read: @escaping @MainActor (String) async throws -> Data) {
    self.item = item
    self.read = read
  }

  static func url(of path: String, asHTML: Bool = false) -> URL? {
    var parts = URLComponents()
    parts.scheme = scheme
    parts.host = "book"
    parts.path = "/" + path
    if asHTML { parts.query = Self.asHTML }
    return parts.url
  }

  /// The book's path of a link in one of its pages, and the anchor after `#`; `nil` for a link out of the book.
  static func place(of url: URL) -> (path: String, anchor: String?)? {
    guard url.scheme == scheme, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    return (String(parts.path.dropFirst()), parts.fragment.flatMap { $0.isEmpty ? nil : $0 })
  }

  func file(_ path: String) async throws -> Data {
    if let data = kept[path] { return data }
    if let pending = fetching[path] { return try await pending.value }
    let task = Task { try await read(path) }
    fetching[path] = task
    defer { fetching[path] = nil }
    let data = try await task.value
    keep(data, at: path)
    return data
  }

  /// Fetches a chapter and the style sheets and pictures it names, in the background.
  func prefetch(_ chapter: String) {
    Task {
      guard let page = try? await file(chapter) else { return }
      for path in Self.references(in: page, of: chapter) where kept[path] == nil {
        _ = try? await file(path)
      }
    }
  }

  static func references(in page: Data, of path: String) -> [String] {
    let text = String(decoding: page, as: UTF8.self)
    let folder = path.split(separator: "/", omittingEmptySubsequences: false).dropLast().map(String.init)
    var found: [String] = []
    for match in text.matches(of: /(?:src|href|xlink:href)\s*=\s*["']([^"'#?]+)["']/) {
      let link = String(match.1)
      guard !link.contains(":"), !link.hasSuffix(".xhtml"), !link.hasSuffix(".html") else { continue }
      var components = folder
      for piece in (link.removingPercentEncoding ?? link).split(separator: "/") {
        switch piece {
        case ".": continue
        case "..": if !components.isEmpty { components.removeLast() }
        default: components.append(String(piece))
        }
      }
      let resolved = components.joined(separator: "/")
      if !found.contains(resolved) { found.append(resolved) }
    }
    return found
  }

  private func keep(_ data: Data, at path: String) {
    kept[path] = data
    order.append(path)
    var total = kept.values.reduce(0) { $0 + $1.count }
    while total > Self.budget, order.count > 1 {
      let oldest = order.removeFirst()
      total -= kept.removeValue(forKey: oldest)?.count ?? 0
    }
  }

  func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
    let key = ObjectIdentifier(task)
    running.insert(key)
    guard let url = task.request.url, let place = Self.place(of: url) else {
      task.didFailWithError(URLError(.badURL))
      return
    }
    let html = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query == Self.asHTML
    Task {
      let data = try? await file(place.path)
      guard running.remove(key) != nil else { return }
      guard let data else {
        task.didFailWithError(URLError(.fileDoesNotExist))
        return
      }
      let type = Self.type(of: place.path, asHTML: html)
      let text = type.hasPrefix("text/") || type.hasSuffix("xml")
      task.didReceive(
        URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: text ? "utf-8" : nil)
      )
      task.didReceive(data)
      task.didFinish()
    }
  }

  func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
    running.remove(ObjectIdentifier(task))
  }

  static func type(of path: String, asHTML: Bool) -> String {
    switch (path as NSString).pathExtension.lowercased() {
    case "xhtml", "xht", "xml": asHTML ? "text/html" : "application/xhtml+xml"
    case "html", "htm": "text/html"
    case "css": "text/css"
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "gif": "image/gif"
    case "webp": "image/webp"
    case "svg": "image/svg+xml"
    case "ttf", "otf", "woff", "woff2": "font/" + (path as NSString).pathExtension.lowercased()
    default: "application/octet-stream"
    }
  }
}
