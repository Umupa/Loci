/// An address of one place inside a piece of content: a sentence, a stretch of time, some lines of code,
/// or a region of a PDF page. Notes, citations and reading positions all use it.
///
/// Written as a `loci://` link. Parsing accepts parameters in any order but rejects anything missing,
/// repeated or unknown; the text form is canonical, so a locator survives text → value → text unchanged.
public enum Locator: Hashable, Sendable, TextCodable {
  case item(EntityID, ItemAnchor)
  /// A lesson can only be pointed into by quoting it.
  case lesson(LessonRef, TextQuote)

  private static let scheme = "loci://"

  public init?(_ description: String) {
    guard description.hasPrefix(Self.scheme) else { return nil }
    let rest = description.dropFirst(Self.scheme.count)
    guard let hash = rest.firstIndex(of: "#"), var fragment = Fragment(rest[rest.index(after: hash)...]) else {
      return nil
    }
    let path = rest[..<hash].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let locator: Locator
    switch path.count {
    case 2 where path[0] == "library":
      guard let item = EntityID(canonical: path[1]), let anchor = ItemAnchor(taking: &fragment) else { return nil }
      locator = .item(item, anchor)
    case 4 where path[0] == "mentor" && path[2] == "lesson":
      guard let mentor = EntityID(canonical: path[1]), let lesson = Lesson.Slug(path[3]),
        let quote = TextQuote(taking: &fragment)
      else { return nil }
      locator = .lesson(LessonRef(mentor: mentor, lesson: lesson), quote)
    default:
      return nil
    }
    guard fragment.isEmpty else { return nil }
    self = locator
  }

  public var description: String {
    switch self {
    case .item(let item, let anchor):
      "\(Self.scheme)library/\(item)#\(anchor.fragment)"
    case .lesson(let lesson, let quote):
      "\(Self.scheme)mentor/\(lesson.mentor)/lesson/\(lesson.lesson)#\(quote.fragment)"
    }
  }
}
