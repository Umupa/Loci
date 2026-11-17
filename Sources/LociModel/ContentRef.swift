/// One piece of content a reader can open: an item in the library, or a mentor's lesson.
public enum ContentRef: Hashable, Codable, Sendable {
  case item(EntityID)
  case lesson(LessonRef)
}

extension Locator {
  /// The content this locator points into.
  public var content: ContentRef {
    switch self {
    case .item(let item, _): .item(item)
    case .lesson(let lesson, _): .lesson(lesson)
    }
  }
}

extension Locator {
  /// Points at a quote in a piece of text content.
  public init(_ quote: TextQuote, in content: ContentRef) {
    switch content {
    case .item(let item): self = .item(item, .quote(quote))
    case .lesson(let lesson): self = .lesson(lesson, quote)
    }
  }

  /// The quoted words this locator points at, if it points by quoting.
  public var quote: TextQuote? {
    switch self {
    case .lesson(_, let quote): quote
    case .item(_, .quote(let quote)): quote
    case .item: nil
    }
  }
}
