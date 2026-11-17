import Foundation

/// A piece of material someone else wrote; the contents of `item.json`. It belongs to no mentor.
public struct Item: Hashable, Sendable {
  public let id: EntityID
  public let kind: Kind
  public let title: String
  public let authors: [String]
  /// Where the item was fetched from; `nil` when it was imported from a local file.
  public let source: URL?
  /// A BCP 47 language tag such as `en` or `zh-Hans`.
  public let language: String?
  /// `nil` until the content has been fetched.
  public let contentHash: ContentHash?
  /// The site, channel or show it comes from, as it names itself.
  public let site: String?
  public let published: Timestamp?

  public init(
    id: EntityID, kind: Kind, title: String, authors: [String] = [], source: URL? = nil, language: String? = nil,
    contentHash: ContentHash? = nil, site: String? = nil, published: Timestamp? = nil
  ) throws {
    if let source, !source.isWebLink { throw ModelError("source is not an http or https link: \(source)") }
    if let language, language.wholeMatch(of: /[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*/) == nil {
      throw ModelError("language is not a BCP 47 tag: \(language)")
    }
    self.id = id
    self.kind = try kind.validated()
    self.title = try title.requiringText("title")
    self.authors = try authors.map { try $0.requiringText("author") }
    self.source = source
    self.language = language
    self.contentHash = contentHash
    self.site = try site.requiringText("site")
    self.published = published
  }

  /// What sort of material an item is. Each kind has its own reader and its own way of pointing inside it.
  public enum Kind: Hashable, Sendable {
    case article
    case paper
    /// The duration is `nil` until the media has been fetched.
    case video(duration: Duration?)
    case audio(duration: Duration?)
    /// A repository is always read at one pinned commit.
    case repository(commit: CommitID)
  }
}

extension Item: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, kind, title, authors, source, language, contentHash, duration, commit, site, published
  }

  private enum KindName: String, Codable {
    case article, paper, video, audio, repository
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let seconds = try container.decodeIfPresent(Double.self, forKey: .duration)
    let commit = try container.decodeIfPresent(CommitID.self, forKey: .commit)
    let name = try container.decode(KindName.self, forKey: .kind)
    if seconds != nil, ![.video, .audio].contains(name) {
      throw DecodingError.dataCorruptedError(
        forKey: .duration, in: container, debugDescription: "\(name) has no duration")
    }
    if commit != nil, name != .repository {
      throw DecodingError.dataCorruptedError(forKey: .commit, in: container, debugDescription: "\(name) has no commit")
    }
    let duration = seconds.map { Duration.milliseconds(Int(($0 * 1000).rounded())) }
    let kind: Kind
    switch name {
    case .article: kind = .article
    case .paper: kind = .paper
    case .video: kind = .video(duration: duration)
    case .audio: kind = .audio(duration: duration)
    case .repository:
      guard let commit else {
        throw DecodingError.keyNotFound(
          CodingKeys.commit, .init(codingPath: decoder.codingPath, debugDescription: "A repository needs a commit"))
      }
      kind = .repository(commit: commit)
    }
    let title = try container.decode(String.self, forKey: .title)
    let authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
    let source = try container.decodeIfPresent(URL.self, forKey: .source)
    let language = try container.decodeIfPresent(String.self, forKey: .language)
    let contentHash = try container.decodeIfPresent(ContentHash.self, forKey: .contentHash)
    let site = try container.decodeIfPresent(String.self, forKey: .site)
    let published = try container.decodeIfPresent(Timestamp.self, forKey: .published)
    let id = try container.decode(EntityID.self, forKey: .id)
    self = try decoder.validated {
      try Item(
        id: id, kind: kind, title: title, authors: authors, source: source, language: language,
        contentHash: contentHash, site: site, published: published)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    switch kind {
    case .article:
      try container.encode(KindName.article, forKey: .kind)
    case .paper:
      try container.encode(KindName.paper, forKey: .kind)
    case .video(let duration):
      try container.encode(KindName.video, forKey: .kind)
      try container.encodeIfPresent(duration.map { Double($0.roundedMilliseconds) / 1000 }, forKey: .duration)
    case .audio(let duration):
      try container.encode(KindName.audio, forKey: .kind)
      try container.encodeIfPresent(duration.map { Double($0.roundedMilliseconds) / 1000 }, forKey: .duration)
    case .repository(let commit):
      try container.encode(KindName.repository, forKey: .kind)
      try container.encode(commit, forKey: .commit)
    }
    try container.encode(title, forKey: .title)
    try container.encode(authors, forKey: .authors)
    try container.encodeIfPresent(source, forKey: .source)
    try container.encodeIfPresent(language, forKey: .language)
    try container.encodeIfPresent(contentHash, forKey: .contentHash)
    try container.encodeIfPresent(site, forKey: .site)
    try container.encodeIfPresent(published, forKey: .published)
  }
}

extension Item.Kind {
  fileprivate func validated() throws -> Self {
    switch self {
    case .video(let duration): .video(duration: try Self.toMilliseconds(duration))
    case .audio(let duration): .audio(duration: try Self.toMilliseconds(duration))
    case .article, .paper, .repository: self
    }
  }

  private static func toMilliseconds(_ duration: Duration?) throws -> Duration? {
    guard let duration else { return nil }
    let milliseconds = duration.roundedMilliseconds
    guard milliseconds > 0 else { throw ModelError("duration is not positive") }
    return .milliseconds(milliseconds)
  }
}
