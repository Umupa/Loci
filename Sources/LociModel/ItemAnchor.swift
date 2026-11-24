/// Where inside an item a locator points. Which anchors suit which kind of item is up to the reader.
public enum ItemAnchor: Hashable, Sendable {
  /// The item as a whole, for a thought on all of it. Written without a fragment.
  case whole
  case time(TimeSpan)
  case quote(TextQuote)
  case page(PageRegion)
  case lines(CodeLines)
  case spot(BookSpot)

  init?(taking fragment: inout Fragment) {
    if let time = fragment.take("t") {
      guard let span = TimeSpan(fragmentValue: time) else { return nil }
      self = .time(span)
    } else if let page = fragment.take("page") {
      guard let region = PageRegion(page: page, taking: &fragment) else { return nil }
      self = .page(region)
    } else if let chapter = fragment.take("chapter") {
      guard let spot = BookSpot(chapter: chapter, taking: &fragment) else { return nil }
      self = .spot(spot)
    } else if let path = fragment.take("path") {
      guard let lines = CodeLines(path: path, taking: &fragment) else { return nil }
      self = .lines(lines)
    } else {
      guard let quote = TextQuote(taking: &fragment) else { return nil }
      self = .quote(quote)
    }
  }

  /// What follows `#`; `nil` for the whole item, which has no `#`.
  var fragment: String? {
    switch self {
    case .whole: nil
    case .time(let span): span.fragment
    case .quote(let quote): quote.fragment
    case .page(let region): region.fragment
    case .lines(let lines): lines.fragment
    case .spot(let spot): spot.fragment
    }
  }
}
