import Foundation
import LociMedia
import LociModel
import LociStore

/// Following channels and shows: the row above the video and podcast galleries, each follow page, and
/// `loci follow`. An episode is in the library when an item was taken in from a link to it.
extension LocalHost {
  public func previewFollow(_ command: PreviewFollow) async throws(HostError) -> FollowPreview {
    try await follows.preview(command.link)
  }

  public func startFollowing(_ command: StartFollowing) async throws(HostError) -> Follow {
    try await follows.start(command.link)
  }

  public func stopFollowing(_ command: StopFollowing) async throws(HostError) -> Follow {
    try await follows.stop(command.follow)
  }

  public func restoreFollowing(_ command: RestoreFollowing) async throws(HostError) -> Done {
    try await follows.restore(command.follow)
    return Done()
  }

  public func sawFollow(_ command: SawFollow) async throws(HostError) -> Done {
    try await follows.saw(command.follow)
    return Done()
  }

  public func refreshFollow(_ command: RefreshFollow) async throws(HostError) -> Done {
    try await follows.refresh(command.follow, again: command.again)
    return Done()
  }

  public func followOfItem(_ command: FollowOfItem) async throws(HostError) -> ItemFollow? {
    let item = try attempt { try store.item(command.item) }
    guard let source = item.source, item.kind.isMedia else { return nil }
    let link: FollowLink?
    if let channel = channel(ofVideo: item.id),
      let page = URL(string: "https://www.youtube.com/channel/\(channel)")
    {
      link = .youtube(page)
    } else {
      link = try? await environment.media.follows.show(ofEpisode: source)
    }
    guard let link else { return nil }
    return ItemFollow(link: link.url, following: store.follows().first { link.leads(to: $0.source) }?.id)
  }

  public func listFollows() async throws(HostError) -> [FollowListing] {
    let kept = keptEpisodes()
    return try attempt {
      try store.follows().map { follow in
        let episodes = try database.episodes(of: follow.id)
        return FollowListing(
          follow: follow, latest: episodes.first?.episode,
          kept: episodes.compactMap { entry in
            kept[entry.episode.key].map { FollowListing.Kept(item: $0.id, title: $0.title) }
          })
      }
    }
  }

  public func followSummaries() async throws(HostError) -> [FollowSummary] {
    let summaries = try attempt {
      try store.follows().map { follow in
        let episodes = try database.episodes(of: follow.id, limit: 20)
        return FollowSummary(
          follow: follow, latest: episodes.first?.episode,
          fresh: episodes.filter { $0.firstSeen > follow.opened }.map(\.episode))
      }
    }
    return summaries.sorted { Self.updated($0) > Self.updated($1) }
  }

  public func followPage(_ id: EntityID) async throws(HostError) -> FollowPage? {
    guard let follow = store.follows().first(where: { $0.id == id }) else { return nil }
    let kept = keptEpisodes()
    return try attempt {
      FollowPage(
        follow: follow,
        entries: try database.episodes(of: id).map { entry in
          FollowPage.Entry(episode: entry.episode, firstSeen: entry.firstSeen, item: kept[entry.episode.key]?.id)
        },
        problem: try database.followState(id).problem)
    }
  }

  /// When a follow last had something come out, for the row's order.
  private static func updated(_ summary: FollowSummary) -> Int64 {
    (summary.latest?.published ?? summary.follow.followed).millisecondsSince1970
  }

  /// The video and audio items, by the episode each was taken in from.
  private func keptEpisodes() -> [EpisodeKey: Item] {
    let items = ((try? database.items()) ?? []).filter(\.kind.isMedia)
    return Dictionary(
      items.compactMap { item in item.source.map { (EpisodeKey($0), item) } }, uniquingKeysWith: { first, _ in first })
  }

  /// The YouTube channel yt-dlp named when the video was taken in.
  private func channel(ofVideo item: EntityID) -> String? {
    struct Named: Decodable {
      let channelId: String?
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let text = try? store.workText(named: JobRun.info, of: item),
      let named = try? decoder.decode(Named.self, from: Data(text.utf8))
    else { return nil }
    return named.channelId
  }
}

extension Item.Kind {
  var isMedia: Bool {
    switch self {
    case .video, .audio: true
    case .article, .paper, .repository, .book: false
    }
  }
}
