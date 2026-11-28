import Foundation

/// A channel or show the person follows; one entry of `follows.json`. Its episodes are read in the background
/// and listed on its follow page, and only the one the person picks is taken into the library.
public struct Follow: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let source: FollowSource
  public let name: String
  /// The line under the name: a channel's handle, or the platform a show is on.
  public let handle: String?
  public let picture: URL?
  /// Its page on the web, to open in a browser.
  public let page: URL
  public let followed: Timestamp
  /// When the follow page was last opened. Episodes first seen after it are new.
  public let opened: Timestamp

  public init(
    id: EntityID, source: FollowSource, name: String, handle: String? = nil, picture: URL? = nil,
    page: URL, followed: Timestamp, opened: Timestamp? = nil
  ) {
    self.id = id
    self.source = source
    self.name = name
    self.handle = handle
    self.picture = picture
    self.page = page
    self.followed = followed
    self.opened = opened ?? followed
  }

  /// The same follow, opened at `time`.
  public func opening(at time: Timestamp) -> Follow {
    Follow(
      id: id, source: source, name: name, handle: handle, picture: picture, page: page, followed: followed,
      opened: time)
  }
}

/// Where a follow's episodes are read from. It decides how they are fetched and whether the follow is a
/// channel of videos or a show of episodes.
public enum FollowSource: Hashable, Codable, Sendable {
  /// A YouTube channel, by its `UC…` id.
  case youtube(channel: String)
  /// A show on 小宇宙, with the same show on Apple Podcasts when one was found, for its past episodes.
  case xiaoyuzhou(podcast: String, apple: Int?)
  /// A show on Apple Podcasts.
  case apple(Int)
  /// A podcast feed, RSS or Atom.
  case feed(URL)

  /// Videos or episodes.
  public var isChannel: Bool {
    if case .youtube = self { return true }
    return false
  }

  /// The same show whoever's link it was read from; a 小宇宙 show is the same with or without Apple's.
  public var identity: String {
    switch self {
    case .youtube(let channel): "youtube/\(channel)"
    case .xiaoyuzhou(let podcast, _): "xiaoyuzhou/\(podcast)"
    case .apple(let id): "apple/\(id)"
    case .feed(let url): "feed/\(url.absoluteString)"
    }
  }
}

/// One video or episode of a follow, as its source lists it.
public struct Episode: Hashable, Codable, Sendable {
  public let key: EpisodeKey
  public let title: String
  /// What the import card is given to take it in.
  public let link: URL
  public let published: Timestamp?
  public let length: Duration?
  public let picture: URL?

  public init(
    title: String, link: URL, published: Timestamp? = nil, length: Duration? = nil, picture: URL? = nil,
    key: EpisodeKey? = nil
  ) {
    self.key = key ?? EpisodeKey(link)
    self.title = title
    self.link = link
    self.published = published
    self.length = length
    self.picture = picture
  }

  /// The same episode with what `other` knows and this one does not, such as a length the feed leaves out.
  public func filled(from other: Episode) -> Episode {
    Episode(
      title: title, link: link, published: published ?? other.published, length: length ?? other.length,
      picture: picture ?? other.picture, key: key)
  }
}

/// Why a follow's episodes could not be read the last time.
public enum FollowProblem: Hashable, Codable, Sendable {
  /// The site wants the person signed in.
  case signIn
  /// The address no longer leads to the channel or show.
  case gone
  /// The site refused this Mac.
  case refused
  /// The site could not be reached.
  case offline
}
