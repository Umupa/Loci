import Foundation

public struct CourseSource: Hashable, Codable, Sendable, Identifiable {
  public enum Kind: String, Hashable, Codable, Sendable {
    case paper, video, repository, page
  }

  public enum Origin: Hashable, Codable, Sendable {
    case paper
    case video
    case repository(CommitID)
    case page

    var kind: Kind {
      switch self {
      case .paper: .paper
      case .video: .video
      case .repository: .repository
      case .page: .page
      }
    }

    var commit: CommitID? {
      if case .repository(let commit) = self { commit } else { nil }
    }
  }

  public struct Draft: Hashable, Codable, Sendable {
    public let url: URL
    public let title: String?
    public let origin: Origin

    public init(url: URL, title: String? = nil, kind: Kind? = nil, commit: CommitID? = nil) throws {
      guard url.isWebLink else { throw ModelError("source url must be an http or https link") }
      self.url = url
      self.title = try title.map { try CourseGoal.line($0, field: "source title") }
      let kind = kind ?? (commit == nil ? Self.predict(url) : .repository)
      switch (kind, commit) {
      case (.repository, let commit?): origin = .repository(commit)
      case (.repository, nil): throw ModelError("a repository needs a full commit SHA")
      case (_, _?): throw ModelError("a commit is only valid for a repository")
      case (.paper, nil): origin = .paper
      case (.video, nil): origin = .video
      case (.page, nil): origin = .page
      }
    }

    private static func predict(_ url: URL) -> Kind {
      switch LinkKind(url) {
      case .paper: .paper
      case .video: .video
      case .audio, .article: .page
      }
    }

    private enum CodingKeys: String, CodingKey {
      case url, title, kind, commit
    }

    public init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      self = try decoder.validated {
        try Draft(
          url: values.decode(URL.self, forKey: .url), title: values.decodeIfPresent(String.self, forKey: .title),
          kind: values.decode(Kind.self, forKey: .kind), commit: values.decodeIfPresent(CommitID.self, forKey: .commit))
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode(url, forKey: .url)
      try values.encodeIfPresent(title, forKey: .title)
      try values.encode(origin.kind, forKey: .kind)
      try values.encodeIfPresent(origin.commit, forKey: .commit)
    }
  }

  public let id: EntityID
  public let url: URL
  public let title: String
  public let site: String
  public let origin: Origin
  public let isRead: Bool
  public var kind: Kind { origin.kind }
  public var commit: CommitID? { origin.commit }

  public init(id: EntityID, from draft: Draft, isRead: Bool = false) {
    self.init(id: id, url: draft.url, title: draft.title, origin: draft.origin, isRead: isRead)
  }

  private init(id: EntityID, url: URL, title: String?, origin: Origin, isRead: Bool) {
    self.id = id
    self.url = url
    site = url.host() ?? url.absoluteString
    self.title = title ?? site
    self.origin = origin
    self.isRead = isRead
  }

  func updated(with draft: Draft) -> CourseSource {
    CourseSource(
      id: id, url: draft.url, title: draft.title ?? title, origin: draft.origin,
      isRead: origin == draft.origin && isRead)
  }

  func read() -> CourseSource {
    CourseSource(id: id, url: url, title: title, origin: origin, isRead: true)
  }

  private enum CodingKeys: String, CodingKey {
    case id, url, title, site, kind, commit, isRead
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let draft = try Draft(from: decoder)
    self.init(
      id: try values.decode(EntityID.self, forKey: .id), from: draft,
      isRead: try values.decode(Bool.self, forKey: .isRead))
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(url, forKey: .url)
    try values.encode(title, forKey: .title)
    try values.encode(site, forKey: .site)
    try values.encode(kind, forKey: .kind)
    try values.encodeIfPresent(commit, forKey: .commit)
    try values.encode(isRead, forKey: .isRead)
  }
}
