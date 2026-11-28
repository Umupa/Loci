import Foundation
import LociModel

/// A YouTube channel as its own page tells it, and its videos as yt-dlp lists them.
struct YouTubeChannel: Hashable, Sendable {
  let id: String
  let name: String
  let handle: String?
  let picture: URL?
  let page: URL

  init(html: String, at url: URL) throws(FollowFailure) {
    guard let id = html.firstMatch(of: /"externalId":"(UC[A-Za-z0-9_-]+)"/).map({ String($0.1) }) else {
      throw FollowFailure(.gone, "\(url): no channel on this page")
    }
    let preview = PageMeta.preview(html: html, at: url)
    self.id = id
    name = preview.title ?? id
    picture = preview.image
    handle = html.firstMatch(of: /"vanityChannelUrl":"https?:\/\/www\.youtube\.com\/(@[^"]+)"/).map { String($0.1) }
    page = URL(string: "https://www.youtube.com/\(handle ?? "channel/\(id)")") ?? url
  }

  static func thumbnail(of video: String) -> URL? {
    URL(string: "https://i.ytimg.com/vi/\(video)/hqdefault.jpg")
  }

  /// The videos in `yt-dlp --flat-playlist -J` of a channel's videos tab, newest first.
  static func videos(json: Data) throws(FollowFailure) -> [Episode] {
    struct Listing: Decodable {
      struct Entry: Decodable {
        let id: String
        let title: String?
        let duration: Double?
        let timestamp: Int64?
      }
      let entries: [Entry]
    }
    let listing: Listing
    do {
      listing = try JSONDecoder().decode(Listing.self, from: json)
    } catch {
      throw FollowFailure(.gone, "yt-dlp listed no videos")
    }
    return listing.entries.compactMap { entry in
      guard let title = entry.title, let link = URL(string: "https://www.youtube.com/watch?v=\(entry.id)") else {
        return nil
      }
      return Episode(
        title: title, link: link, published: entry.timestamp.map { Timestamp(millisecondsSince1970: $0 * 1000) },
        length: entry.duration.map { .seconds($0) }, picture: thumbnail(of: entry.id))
    }
  }
}

/// A show on 小宇宙 as its page's `__NEXT_DATA__` tells it: its name, cover and newest episodes.
struct XiaoyuzhouShow: Hashable, Sendable {
  let name: String
  let picture: URL?
  let episodes: [Episode]

  static func page(_ podcast: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.xiaoyuzhoufm.com"
    components.path = "/podcast/\(podcast)"
    return components.url ?? URL(filePath: "/")
  }

  static func episodePage(_ episode: String) -> URL? {
    URL(string: "https://www.xiaoyuzhoufm.com/episode/\(episode)")
  }

  init(html: String, at url: URL) throws(FollowFailure) {
    struct Next: Decodable {
      struct Props: Decodable { let pageProps: PageProps }
      struct PageProps: Decodable { let podcast: Podcast }
      struct Picture: Decodable { let picUrl: String? }
      struct Podcast: Decodable {
        let title: String
        let image: Picture?
        let episodes: [Show]?
      }
      struct Show: Decodable {
        let eid: String
        let title: String
        let duration: Double?
        let pubDate: String?
        let image: Picture?
      }
      let props: Props
    }
    guard
      let data = html.firstMatch(of: /<script id="__NEXT_DATA__" type="application\/json">(.*?)<\/script>/)
        .map({ Data($0.1.utf8) }),
      let next = try? JSONDecoder().decode(Next.self, from: data)
    else { throw FollowFailure(.gone, "\(url): no show on this page") }
    let show = next.props.pageProps.podcast
    name = show.title
    picture = show.image?.picUrl.flatMap(URL.init(string:))
    let cover = picture
    episodes = (show.episodes ?? []).compactMap { episode in
      guard let link = Self.episodePage(episode.eid) else { return nil }
      return Episode(
        title: episode.title, link: link, published: episode.pubDate.flatMap(FeedContents.date),
        length: episode.duration.map { .seconds($0) },
        picture: episode.image?.picUrl.flatMap(URL.init(string:)) ?? cover)
    }
  }

  /// An episode Apple lists for a 小宇宙 show, linked to its page on 小宇宙: Apple keeps 小宇宙's episode id as
  /// the guid.
  static func episode(_ apple: AppleShow.Entry) -> Episode {
    guard let guid = apple.guid, guid.wholeMatch(of: /[0-9a-f]{24}/) != nil, let link = episodePage(guid) else {
      return apple.episode
    }
    let episode = apple.episode
    return Episode(
      title: episode.title, link: link, published: episode.published, length: episode.length,
      picture: episode.picture)
  }
}

/// A show as Apple's public lookup tells it.
struct AppleShow: Hashable, Sendable {
  let name: String
  let picture: URL?
  let page: URL
  let entries: [Entry]

  var episodes: [Episode] { entries.map(\.episode) }

  struct Entry: Hashable, Sendable {
    let episode: Episode
    let guid: String?
  }

  static func lookup(_ id: Int, most: Int) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = "/lookup"
    components.queryItems = [
      URLQueryItem(name: "id", value: "\(id)"), URLQueryItem(name: "entity", value: "podcastEpisode"),
      URLQueryItem(name: "limit", value: "\(most)"),
    ]
    return components.url ?? URL(filePath: "/")
  }

  static func search(_ name: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = "/search"
    components.queryItems = [
      URLQueryItem(name: "term", value: name), URLQueryItem(name: "media", value: "podcast"),
      URLQueryItem(name: "limit", value: "10"),
    ]
    return components.url ?? URL(filePath: "/")
  }

  private struct Answer: Decodable {
    struct Result: Decodable {
      let wrapperType: String?
      let kind: String?
      let collectionId: Int?
      let collectionName: String?
      let collectionViewUrl: String?
      let feedUrl: String?
      let artworkUrl600: String?
      let artworkUrl160: String?
      let trackName: String?
      let trackViewUrl: String?
      let releaseDate: String?
      let trackTimeMillis: Int64?
      let episodeGuid: String?
    }
    let results: [Result]
  }

  init(json: Data, at url: URL) throws(FollowFailure) {
    guard let answer = try? JSONDecoder().decode(Answer.self, from: json),
      let show = answer.results.first(where: { $0.kind == "podcast" }), let name = show.collectionName,
      let page = show.collectionViewUrl.flatMap(URL.init(string:))
    else { throw FollowFailure(.gone, "\(url): Apple Podcasts has no such show") }
    self.name = name
    self.page = page
    picture = show.artworkUrl600.flatMap(URL.init(string:))
    entries = answer.results.compactMap { result in
      guard result.wrapperType == "podcastEpisode", let title = result.trackName,
        let link = result.trackViewUrl.flatMap(URL.init(string:))
      else { return nil }
      let episode = Episode(
        title: title, link: link, published: result.releaseDate.flatMap(FeedContents.date),
        length: result.trackTimeMillis.map { .milliseconds($0) },
        picture: (result.artworkUrl600 ?? result.artworkUrl160).flatMap(URL.init(string:)))
      return Entry(episode: episode, guid: result.episodeGuid)
    }
  }

  /// The show Apple lists under `name` whose feed is on 小宇宙; `nil` when there is none.
  static func find(_ name: String, in json: Data) -> Int? {
    guard let answer = try? JSONDecoder().decode(Answer.self, from: json) else { return nil }
    return answer.results.first { result in
      let host = result.feedUrl.flatMap(URL.init(string:))?.host()?.lowercased() ?? ""
      return result.collectionName == name && (host.hasSuffix("xyzfm.space") || host.hasSuffix("xiaoyuzhoufm.com"))
    }?.collectionId
  }
}
