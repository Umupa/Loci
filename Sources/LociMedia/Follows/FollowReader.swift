import Foundation
import LociModel

/// Why a follow could not be read, and what the site said.
public struct FollowFailure: Error, Hashable, Sendable {
  public let problem: FollowProblem
  public let reason: String

  public init(_ problem: FollowProblem, _ reason: String) {
    self.problem = problem
    self.reason = reason
  }

  /// What a failed GET means for a follow: who must sign in, what is gone, what refused this Mac.
  init(_ error: FetchError, at url: URL) {
    let status = error.reason.firstMatch(of: /HTTP (\d{3})/).flatMap { Int($0.1) }
    let problem: FollowProblem =
      switch status {
      case 401: .signIn
      case 403, 429: .refused
      case 404, 410: .gone
      case .some(let code) where code < 500: .gone
      default: error.needsLogin ? .signIn : .offline
      }
    self.init(problem, "\(url.absoluteString): \(error.reason)")
  }
}

/// Reads who a follow is and its episodes. The newest are read with plain GETs only; a YouTube channel's past
/// videos are listed by yt-dlp, which runs only when the person asks for them.
public protocol FollowReading: Sendable {
  /// Who a followable link leads to and its newest episodes.
  func preview(_ link: FollowLink) async throws(FollowFailure) -> FollowPreview
  /// The newest episodes, newest first.
  func latest(_ source: FollowSource) async throws(FollowFailure) -> [Episode]
  /// As many past episodes as the source gives, newest first; a channel's are listed by `ytDlp`, and are
  /// only the newest without it.
  func past(_ follow: Follow, ytDlp: YtDlp?) async throws(FollowFailure) -> [Episode]
  /// The channel or show an episode's link belongs to, when it can be followed.
  func show(ofEpisode link: URL) async throws(FollowFailure) -> FollowLink?
}

/// Reads follows over `network` as no one: no cookies, a browser's User-Agent, the size and time limits of
/// data sources.
public struct FollowReader: FollowReading {
  let network: any Network
  /// The most videos of a channel listed at once.
  static let mostVideos = 60

  public init(network: any Network) {
    self.network = network
  }

  public func preview(_ link: FollowLink) async throws(FollowFailure) -> FollowPreview {
    switch link {
    case .youtube(let page):
      let channel = try YouTubeChannel(html: try await text(page), at: page)
      let episodes = try await latest(.youtube(channel: channel.id))
      return FollowPreview(
        source: .youtube(channel: channel.id), name: channel.name, handle: channel.handle, picture: channel.picture,
        page: channel.page, episodes: episodes)
    case .xiaoyuzhou(let podcast):
      let page = XiaoyuzhouShow.page(podcast)
      let show = try XiaoyuzhouShow(html: try await text(page), at: page)
      let apple = await appleShow(named: show.name)
      return FollowPreview(
        source: .xiaoyuzhou(podcast: podcast, apple: apple), name: show.name, picture: show.picture, page: page,
        episodes: show.episodes)
    case .apple(let id):
      let url = AppleShow.lookup(id, most: 20)
      let show = try AppleShow(json: try await get(url), at: url)
      return FollowPreview(
        source: .apple(id), name: show.name, picture: show.picture, page: show.page, episodes: show.episodes)
    case .feed(let url):
      guard let feed = FeedContents(try await get(url)) else { throw FollowFailure(.gone, "\(url): not a feed") }
      return FollowPreview(
        source: .feed(url), name: feed.title.isEmpty ? PageMeta.domain(of: url) : feed.title, picture: feed.picture,
        page: url, episodes: feed.episodes)
    }
  }

  public func latest(_ source: FollowSource) async throws(FollowFailure) -> [Episode] {
    switch source {
    case .youtube(let channel):
      guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channel)") else {
        throw FollowFailure(.gone, "not a channel: \(channel)")
      }
      guard let feed = FeedContents(try await get(url)) else { throw FollowFailure(.gone, "\(url): not a feed") }
      return feed.episodes
    case .xiaoyuzhou(let podcast, _):
      let page = XiaoyuzhouShow.page(podcast)
      return try XiaoyuzhouShow(html: try await text(page), at: page).episodes
    case .apple(let id):
      let url = AppleShow.lookup(id, most: 20)
      return try AppleShow(json: try await get(url), at: url).episodes
    case .feed(let url):
      guard let feed = FeedContents(try await get(url)) else { throw FollowFailure(.gone, "\(url): not a feed") }
      return feed.episodes
    }
  }

  public func past(_ follow: Follow, ytDlp: YtDlp?) async throws(FollowFailure) -> [Episode] {
    switch follow.source {
    case .youtube:
      guard let ytDlp else { return try await latest(follow.source) }
      let listing: Data
      do throws(MediaError) {
        listing = try await ytDlp.channelVideos(follow.page, most: Self.mostVideos)
      } catch {
        throw FollowFailure(error.kind == .needsLogin ? .signIn : .offline, error.reason)
      }
      return try YouTubeChannel.videos(json: listing)
    case .xiaoyuzhou(_, let apple?):
      let url = AppleShow.lookup(apple, most: 200)
      return try AppleShow(json: try await get(url), at: url).entries.map(XiaoyuzhouShow.episode)
    case .apple(let id):
      let url = AppleShow.lookup(id, most: 200)
      return try AppleShow(json: try await get(url), at: url).episodes
    case .xiaoyuzhou, .feed:
      return try await latest(follow.source)
    }
  }

  public func show(ofEpisode link: URL) async throws(FollowFailure) -> FollowLink? {
    let host = link.host()?.lowercased() ?? ""
    switch EpisodeKey(link).description.split(separator: "/").first {
    case "apple":
      guard let id = link.pathComponents.last.flatMap({ $0.hasPrefix("id") ? Int($0.dropFirst(2)) : nil }) else {
        return nil
      }
      return .apple(id)
    case "youtube":
      guard let channel = try await text(link).firstMatch(of: /"channelId":"(UC[A-Za-z0-9_-]{22})"/),
        let page = URL(string: "https://www.youtube.com/channel/\(channel.1)")
      else { return nil }
      return .youtube(page)
    case "xiaoyuzhou" where host.hasSuffix("xiaoyuzhoufm.com"):
      return try await text(link).firstMatch(of: /"pid":\s*"([0-9a-f]{24})"/).map { .xiaoyuzhou(String($0.1)) }
    default:
      return nil
    }
  }

  /// The same show on Apple Podcasts, for its past episodes; `nil` when Apple has none or cannot be asked.
  private func appleShow(named name: String) async -> Int? {
    do throws(FollowFailure) {
      return AppleShow.find(name, in: try await get(AppleShow.search(name)))
    } catch {
      return nil
    }
  }

  private func get(_ url: URL) async throws(FollowFailure) -> Data {
    var request = URLRequest(url: url, timeoutInterval: SourceFetcher.timeout)
    request.httpMethod = "GET"
    request.httpShouldHandleCookies = false
    request.setValue(SourceFetcher.userAgent, forHTTPHeaderField: "User-Agent")
    let data: Data
    do {
      (data, _) = try await network.data(for: request)
    } catch {
      throw FollowFailure(error, at: url)
    }
    guard data.count <= SourceFetcher.mostBytes else { throw FollowFailure(.gone, "\(url): the page is too large") }
    return data
  }

  private func text(_ url: URL) async throws(FollowFailure) -> String {
    String(decoding: try await get(url), as: UTF8.self)
  }
}
