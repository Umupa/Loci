import Foundation

/// What a followable link leads to, for the follow card: who it is and the latest three episodes. `following`
/// is the follow it already is, if it is one.
public struct FollowPreview: Hashable, Codable, Sendable {
  public let source: FollowSource
  public let name: String
  public let handle: String?
  public let picture: URL?
  public let page: URL
  /// Newest first.
  public let episodes: [Episode]
  public let following: EntityID?

  public init(
    source: FollowSource, name: String, handle: String? = nil, picture: URL? = nil, page: URL, episodes: [Episode],
    following: EntityID? = nil
  ) {
    self.source = source
    self.name = name
    self.handle = handle
    self.picture = picture
    self.page = page
    self.episodes = episodes
    self.following = following
  }

  public func following(_ follow: EntityID?) -> FollowPreview {
    FollowPreview(
      source: source, name: name, handle: handle, picture: picture, page: page, episodes: episodes, following: follow)
  }
}

/// One follow in the row above the gallery: the newest episode, and the episodes the person has not seen yet,
/// newest first.
public struct FollowSummary: Hashable, Codable, Sendable, Identifiable {
  public let follow: Follow
  public let latest: Episode?
  public let fresh: [Episode]

  public var id: EntityID { follow.id }

  public init(follow: Follow, latest: Episode?, fresh: [Episode]) {
    self.follow = follow
    self.latest = latest
    self.fresh = fresh
  }
}

/// A follow page: the follow, its episodes newest first, and why they could not be read the last time.
public struct FollowPage: Hashable, Codable, Sendable {
  public let follow: Follow
  public let entries: [Entry]
  public let problem: FollowProblem?

  public init(follow: Follow, entries: [Entry], problem: FollowProblem?) {
    self.follow = follow
    self.entries = entries
    self.problem = problem
  }

  /// One episode on the page, with the item it was taken in as.
  public struct Entry: Hashable, Codable, Sendable, Identifiable {
    public let episode: Episode
    public let firstSeen: Timestamp
    public let item: EntityID?

    public var id: EpisodeKey { episode.key }

    public init(episode: Episode, firstSeen: Timestamp, item: EntityID?) {
      self.episode = episode
      self.firstSeen = firstSeen
      self.item = item
    }

    /// First seen after the follow page was last opened at `opened`.
    public func isNew(since opened: Timestamp) -> Bool {
      firstSeen > opened
    }
  }
}

/// A follow as `loci follow list` tells it: the newest episode, and the episodes taken into the library.
public struct FollowListing: Hashable, Codable, Sendable {
  public let follow: Follow
  public let latest: Episode?
  public let kept: [Kept]

  public init(follow: Follow, latest: Episode?, kept: [Kept]) {
    self.follow = follow
    self.latest = latest
    self.kept = kept
  }

  public struct Kept: Hashable, Codable, Sendable {
    public let item: EntityID
    public let title: String

    public init(item: EntityID, title: String) {
      self.item = item
      self.title = title
    }
  }
}

/// Where an item came from, when it can be followed: the channel's or show's link, and the follow it already is.
public struct ItemFollow: Hashable, Codable, Sendable {
  public let link: URL
  public let following: EntityID?

  public init(link: URL, following: EntityID?) {
    self.link = link
    self.following = following
  }
}
