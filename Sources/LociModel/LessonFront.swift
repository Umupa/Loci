import Foundation

extension Lesson {
  /// The front matter at the top of a lesson's text: the sources it draws on.
  public struct Front: Hashable, Sendable {
    public let sources: [Source]

    public init(sources: [Source]) throws {
      guard Set(sources).count == sources.count else { throw ModelError("a source is listed twice") }
      self.sources = sources
    }

    /// The citations these sources make. Links that have not been fetched yet cite nothing.
    public func citations(in lesson: LessonRef) -> [Citation] {
      sources.compactMap { source in
        guard case .item(let item) = source else { return nil }
        return Citation(lesson: lesson, item: item, anchor: nil)
      }
    }
  }

  /// One entry in a lesson's sources: an item in the library, or a link the app has yet to fetch into it.
  ///
  /// Written as the item's id or as the link itself.
  public enum Source: Hashable, Sendable, TextCodable {
    case item(EntityID)
    case link(URL)

    public init?(_ description: String) {
      if let id = EntityID(canonical: description) {
        self = .item(id)
      } else if let url = URL(string: description), url.isWebLink {
        self = .link(url)
      } else {
        return nil
      }
    }

    public var description: String {
      switch self {
      case .item(let id): id.description
      case .link(let url): url.absoluteString
      }
    }
  }
}

extension Lesson.Front: Codable {
  private enum CodingKeys: String, CodingKey {
    case sources
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let sources = try container.decodeIfPresent([Lesson.Source].self, forKey: .sources) ?? []
    self = try decoder.validated { try Lesson.Front(sources: sources) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(sources, forKey: .sources)
  }
}
