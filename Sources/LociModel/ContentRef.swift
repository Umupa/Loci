/// One piece of content a reader can open: an item in the library.
public enum ContentRef: Hashable, Codable, Sendable {
  case item(EntityID)
}

extension Locator {
  /// The content this locator points into.
  public var content: ContentRef {
    switch self {
    case .item(let item, _): .item(item)
    }
  }
}

extension Locator {
  /// Points at a quote in a piece of text content.
  public init(_ quote: TextQuote, in content: ContentRef) {
    switch content {
    case .item(let item): self = .item(item, .quote(quote))
    }
  }

  /// The quoted words this locator points at, if it points by quoting.
  public var quote: TextQuote? {
    switch self {
    case .item(_, .quote(let quote)): quote
    case .item: nil
    }
  }
}
