import Foundation

/// A link to something that can be followed, told from the address alone: a YouTube channel, a show on 小宇宙
/// or Apple Podcasts, or a podcast feed. A link to one video or episode is not one.
public enum FollowLink: Hashable, Codable, Sendable {
  /// A YouTube channel's page, without the tab it was opened at.
  case youtube(URL)
  /// A 小宇宙 show, by its id.
  case xiaoyuzhou(String)
  /// An Apple Podcasts show, by its id.
  case apple(Int)
  /// An RSS or Atom feed.
  case feed(URL)

  public init?(_ url: URL) {
    guard url.isWebLink, let host = url.host()?.lowercased() else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    if Self.matches(host, "youtube.com") {
      guard let page = Self.channel(parts, query: url) else { return nil }
      self = .youtube(page)
    } else if Self.matches(host, "xiaoyuzhoufm.com") {
      guard parts.count >= 2, parts[0] == "podcast", !parts[1].isEmpty else { return nil }
      self = .xiaoyuzhou(parts[1])
    } else if Self.matches(host, "podcasts.apple.com") {
      guard Self.query(url, "i") == nil, let last = parts.last, last.hasPrefix("id"), let id = Int(last.dropFirst(2))
      else { return nil }
      self = .apple(id)
    } else if Self.isFeed(host: host, parts: parts, extension: url.pathExtension.lowercased()) {
      self = .feed(url)
    } else {
      return nil
    }
  }

  /// The link itself, to follow or open.
  public var url: URL {
    var components = URLComponents()
    components.scheme = "https"
    switch self {
    case .youtube(let page), .feed(let page): return page
    case .xiaoyuzhou(let podcast):
      components.host = "www.xiaoyuzhoufm.com"
      components.path = "/podcast/\(podcast)"
    case .apple(let id):
      components.host = "podcasts.apple.com"
      components.path = "/podcast/id\(id)"
    }
    return components.url ?? URL(filePath: "/")
  }

  /// Whether a follow of `source` is what this link leads to, as far as the address tells.
  public func leads(to source: FollowSource) -> Bool {
    switch (self, source) {
    case (.youtube(let page), .youtube(let channel)):
      page.pathComponents.suffix(2) == ["channel", channel]
    case (.xiaoyuzhou(let podcast), .xiaoyuzhou(let followed, _)): podcast == followed
    case (.apple(let id), .apple(let followed)), (.apple(let id), .xiaoyuzhou(_, let followed?)): id == followed
    case (.feed(let url), .feed(let followed)): url == followed
    default: false
    }
  }

  private static let tabs: Set = ["videos", "streams", "shorts", "featured", "playlists", "podcasts", "about"]

  private static func channel(_ parts: [String], query url: URL) -> URL? {
    guard let first = parts.first else { return nil }
    let base: [String]
    if first.hasPrefix("@"), first.count > 1 {
      base = [first]
    } else if ["channel", "c", "user"].contains(first), parts.count >= 2 {
      base = Array(parts.prefix(2))
    } else if first == "feeds", let channel = query(url, "channel_id") {
      base = ["channel", channel]
    } else {
      return nil
    }
    guard parts.count == base.count || (first != "feeds" && tabs.contains(parts[base.count])) else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.youtube.com"
    components.path = "/" + base.joined(separator: "/")
    return components.url
  }

  private static func isFeed(host: String, parts: [String], extension: String) -> Bool {
    if ["xml", "rss", "atom"].contains(`extension`) { return true }
    if host.hasPrefix("feed.") || host.hasPrefix("feeds.") { return true }
    return parts.contains { ["feed", "rss", "feeds"].contains($0.lowercased()) }
  }

  static func query(_ url: URL, _ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
      .flatMap { $0.isEmpty ? nil : $0 }
  }

  static func matches(_ host: String, _ domain: String) -> Bool {
    host == domain || host.hasSuffix("." + domain)
  }
}

/// Tells that two links lead to the same video or episode, so an episode on a follow page is known to be in
/// the library whichever of its links the item was taken in by.
public struct EpisodeKey: Hashable, Codable, Sendable, CustomStringConvertible {
  public let description: String

  public init(_ link: URL) {
    let host = (link.host() ?? "").lowercased()
    let parts = link.pathComponents.filter { $0 != "/" }
    if FollowLink.matches(host, "youtube.com") {
      if let video = FollowLink.query(link, "v") {
        description = "youtube/\(video)"
        return
      }
      if parts.count >= 2, ["shorts", "live", "embed"].contains(parts[0]) {
        description = "youtube/\(parts[1])"
        return
      }
    }
    if FollowLink.matches(host, "youtu.be"), let video = parts.first {
      description = "youtube/\(video)"
    } else if FollowLink.matches(host, "xiaoyuzhoufm.com"), parts.count >= 2, parts[0] == "episode" {
      description = "xiaoyuzhou/\(parts[1])"
    } else if FollowLink.matches(host, "podcasts.apple.com"), let episode = FollowLink.query(link, "i") {
      description = "apple/\(episode)"
    } else {
      let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
      let path = link.path().hasSuffix("/") ? String(link.path().dropLast()) : link.path()
      description = "link/\(site)\(path)" + (link.query().map { "?\($0)" } ?? "")
    }
  }

  public init(_ text: String) {
    description = text
  }

  public init(from decoder: any Decoder) throws {
    description = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}
