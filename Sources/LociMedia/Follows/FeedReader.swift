import Foundation
import LociModel

/// What an RSS 2.0 or Atom feed says about a show and its episodes. YouTube's channel feed is Atom with each
/// video's id and thumbnail; a podcast's is RSS with an enclosure for each episode. An entry with neither a
/// video nor audio is left out.
struct FeedContents: Hashable, Sendable {
  let title: String
  let author: String?
  let picture: URL?
  /// In the feed's order, usually newest first.
  let episodes: [Episode]

  /// `nil` when the data is not a feed.
  init?(_ data: Data) {
    let reader = FeedParser()
    let parser = XMLParser(data: data)
    parser.delegate = reader
    parser.shouldProcessNamespaces = false
    guard parser.parse(), reader.isFeed else { return nil }
    title = reader.title.trimmingCharacters(in: .whitespacesAndNewlines)
    author = reader.author.flatMap { $0.isEmpty ? nil : $0 }
    picture = reader.picture
    episodes = reader.entries.compactMap(\.episode)
  }

  /// RFC 822 dates as RSS writes them, and ISO 8601 as Atom does.
  static func date(_ text: String) -> Timestamp? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let moment = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
      return Timestamp(moment)
    }
    if let moment = try? Date.ISO8601FormatStyle().parse(text) { return Timestamp(moment) }
    for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = format
      if let moment = formatter.date(from: text) { return Timestamp(moment) }
    }
    return nil
  }

  /// `1:13:30`, `45:02` or plain seconds.
  static func length(_ text: String) -> Duration? {
    let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").map { Double($0) }
    guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
    let seconds = parts.compactMap(\.self).reduce(0) { $0 * 60 + $1 }
    return seconds > 0 ? .seconds(seconds) : nil
  }
}

/// One `<item>` or `<entry>` as read.
private struct FeedEntry {
  var title = ""
  var link: URL?
  var video: String?
  var enclosure: URL?
  var published: String?
  var length: String?
  var picture: URL?

  var episode: Episode? {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    let when = published.flatMap(FeedContents.date)
    let length = length.flatMap(FeedContents.length)
    if let video, let watch = URL(string: "https://www.youtube.com/watch?v=\(video)") {
      return Episode(title: title, link: watch, published: when, length: length, picture: picture)
    }
    guard let enclosure else { return nil }
    let page = link.flatMap { LinkKind($0) == .audio ? $0 : nil }
    return Episode(title: title, link: page ?? enclosure, published: when, length: length, picture: picture)
  }
}

private final class FeedParser: NSObject, XMLParserDelegate {
  var isFeed = false
  var title = ""
  var author: String?
  var picture: URL?
  var entries: [FeedEntry] = []
  private var entry: FeedEntry?
  private var path: [String] = []
  private var text = ""

  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
    attributes: [String: String]
  ) {
    path.append(name)
    text = ""
    switch name {
    case "rss", "feed": isFeed = true
    case "item", "entry": entry = FeedEntry()
    case "enclosure":
      if entry != nil, attributes["type"]?.hasPrefix("video/") != true || entry?.enclosure == nil {
        entry?.enclosure = attributes["url"].flatMap(URL.init(string:))
      }
    case "itunes:image", "media:thumbnail":
      let url = (attributes["href"] ?? attributes["url"]).flatMap(URL.init(string:))
      if let current = entry {
        entry?.picture = current.picture ?? url
      } else {
        picture = picture ?? url
      }
    case "link" where attributes["href"] != nil:
      let url = attributes["href"].flatMap(URL.init(string:))
      if entry != nil, attributes["rel"] ?? "alternate" == "alternate" { entry?.link = url }
    default: break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(_ parser: XMLParser, foundCDATA block: Data) {
    text += String(decoding: block, as: UTF8.self)
  }

  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    defer { path.removeLast() }
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let parent = path.dropLast().last
    if entry != nil {
      switch name {
      case "item", "entry":
        if let entry { entries.append(entry) }
        entry = nil
      case "title" where parent == "item" || parent == "entry": entry?.title = value
      case "link" where !value.isEmpty: entry?.link = URL(string: value)
      case "yt:videoId": entry?.video = value
      case "pubDate", "published": entry?.published = value
      case "updated": if entry?.published == nil { entry?.published = value }
      case "itunes:duration": entry?.length = value
      default: break
      }
      return
    }
    switch name {
    case "title" where parent == "channel" || parent == "feed": title = value
    case "itunes:author": author = value
    case "name" where parent == "author" && path.dropLast(2).last == "feed": author = author ?? value
    case "url" where parent == "image": picture = picture ?? URL(string: value)
    default: break
    }
  }
}
