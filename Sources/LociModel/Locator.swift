/// An address of one place inside a piece of content: a sentence, a stretch of time, some lines of code,
/// or a region of a PDF page, or an item as a whole. Notes, memories and reading positions all use it.
///
/// Written as a `loci://` link. Parsing accepts parameters in any order but rejects anything missing,
/// repeated or unknown; the text form is canonical, so a locator survives text → value → text unchanged.
public enum Locator: Hashable, Sendable, TextCodable {
  case item(EntityID, ItemAnchor)
  case lesson(course: EntityID, lesson: Lesson.ID, quote: TextQuote)

  static let scheme = "loci://"

  public init?(_ description: String) {
    guard description.hasPrefix(Self.scheme) else { return nil }
    let rest = description.dropFirst(Self.scheme.count)
    guard let hash = rest.firstIndex(of: "#") else {
      guard let whole = Self.wholeItem(rest) else { return nil }
      self = whole
      return
    }
    guard var fragment = Fragment(rest[rest.index(after: hash)...]) else { return nil }
    let path = rest[..<hash].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    switch path.first {
    case "library":
      guard path.count == 2, let item = EntityID(canonical: path[1]),
        let anchor = ItemAnchor(taking: &fragment), fragment.isEmpty
      else { return nil }
      self = .item(item, anchor)
    case "courses":
      guard path.count == 3, let course = EntityID(canonical: path[1]), let lesson = Lesson.ID(path[2]),
        let quote = TextQuote(taking: &fragment), fragment.isEmpty
      else { return nil }
      self = .lesson(course: course, lesson: lesson, quote: quote)
    default:
      return nil
    }
  }

  private static func wholeItem(_ path: Substring) -> Locator? {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0] == "library", let item = EntityID(canonical: String(parts[1])) else { return nil }
    return .item(item, .whole)
  }

  public var description: String {
    switch self {
    case .item(let item, let anchor):
      "\(Self.scheme)library/\(item)" + (anchor.fragment.map { "#" + $0 } ?? "")
    case .lesson(let course, let lesson, let quote): "\(Self.scheme)courses/\(course)/\(lesson)#\(quote.fragment)"
    }
  }
}
