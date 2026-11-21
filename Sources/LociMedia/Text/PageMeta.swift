import Foundation
import LociModel

/// What a page's `<head>` says about it: Open Graph first, then Twitter's tags, then the plain title and
/// description.
public enum PageMeta {
  public static func preview(html: String, at url: URL) -> LinkPreview {
    let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.lowerBound]) } ?? html
    let tags = metaTags(in: head)
    func first(_ names: String...) -> String? {
      names.lazy.compactMap { tags[$0] }.first { !$0.isEmpty }
    }
    let image = first("og:image", "og:image:url", "twitter:image").flatMap { URL(string: $0, relativeTo: url) }
    let site = first("og:site_name") ?? domain(of: url)
    return LinkPreview(
      url: url,
      title: (first("og:title", "twitter:title") ?? title(in: head)).map { trimmed($0, site: site, url: url) },
      site: site,
      summary: first("og:description", "twitter:description", "description"),
      image: image?.absoluteURL)
  }

  /// A title without the site's name before or after it, which the card says on its own line; and for a
  /// page that names its address first, `owner/repo: what it is`, only the address.
  static func trimmed(_ title: String, site: String, url: URL) -> String {
    var title = title
    let separators = [" - ", " | ", " · ", " — ", " – ", ": "]
    for separator in separators {
      if title.lowercased().hasPrefix((site + separator).lowercased()) {
        title = String(title.dropFirst(site.count + separator.count))
      } else if title.lowercased().hasSuffix((separator + site).lowercased()) {
        title = String(title.dropLast(site.count + separator.count))
      }
    }
    let path = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if !path.isEmpty, title.lowercased().hasPrefix(path.lowercased() + ":") {
      title = String(title.prefix(path.count))
    }
    let clean = title.trimmingCharacters(in: .whitespaces)
    return clean.isEmpty ? site : clean
  }

  /// The address's host without `www.`: `github.com`.
  public static func domain(of url: URL) -> String {
    let host = url.host() ?? url.absoluteString
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  /// Each `<meta>`'s `property` or `name`, lowercased, with its `content`; the first of a name wins.
  private static func metaTags(in head: String) -> [String: String] {
    var tags: [String: String] = [:]
    for tag in head.matches(of: /(?i)<meta\b[^>]*>/) {
      let attributes = attributes(of: String(tag.output))
      guard let name = attributes["property"] ?? attributes["name"], let content = attributes["content"] else {
        continue
      }
      let key = name.lowercased()
      if tags[key] == nil { tags[key] = decoded(content).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return tags
  }

  private static func attributes(of tag: String) -> [String: String] {
    var attributes: [String: String] = [:]
    for match in tag.matches(of: /([A-Za-z:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/) {
      let value = match.output.2 ?? match.output.3 ?? match.output.4 ?? ""
      attributes[match.output.1.lowercased()] = String(value)
    }
    return attributes
  }

  private static func title(in head: String) -> String? {
    guard let match = head.firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/) else { return nil }
    let title = decoded(String(match.output.1)).trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : title
  }

  /// Character references, named and numeric, as the characters they stand for.
  static func decoded(_ text: String) -> String {
    guard text.contains("&") else { return text }
    let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
    return text.replacing(/&(#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);/) { match in
      let name = String(match.output.1)
      if name.hasPrefix("#") {
        let digits = name.dropFirst()
        let value =
          digits.first.map { "xX".contains($0) } == true
          ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
        return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.output.0)
      }
      return named[name.lowercased()] ?? String(match.output.0)
    }
  }
}

/// Reads link previews and their pictures through the network, once per address while the app runs.
public actor LinkPreviewReader {
  private let network: any Network
  private var previews: [URL: Task<LinkPreview, Never>] = [:]
  private var images: [URL: Task<Data?, Never>] = [:]

  public init(network: any Network) {
    self.network = network
  }

  /// The page's preview; a page that cannot be read gives only its site, and is not asked again.
  public func preview(of url: URL) async -> LinkPreview {
    if let known = previews[url] { return await known.value }
    let network = network
    let task = Task {
      let fallback = LinkPreview(url: url, title: nil, site: PageMeta.domain(of: url), summary: nil, image: nil)
      guard let (data, _) = try? await network.data(for: Self.request(url)) else { return fallback }
      let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
      return PageMeta.preview(html: html, at: url)
    }
    previews[url] = task
    return await task.value
  }

  /// The picture the page's preview names.
  public func image(of url: URL) async -> Data? {
    guard let picture = await preview(of: url).image else { return nil }
    if let known = images[picture] { return await known.value }
    let network = network
    let task = Task { try? await network.data(for: Self.request(picture)).0 }
    images[picture] = task
    return await task.value
  }

  private static func request(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("text/html,image/*;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
    return request
  }
}
