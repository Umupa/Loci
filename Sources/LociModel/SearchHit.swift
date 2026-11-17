/// One place a search found: what it is, which part of it matched, and the words around the match.
public struct SearchHit: Hashable, Codable, Sendable {
  public let target: Target
  public let field: Field
  /// The original text around the first match, on one line.
  public let snippet: String
  /// For a match in an item's text, a quote locator for the matched words; for a note, the note's own
  /// locator. `nil` for names and titles.
  public let locator: Locator?

  public init(target: Target, field: Field, snippet: String, locator: Locator?) {
    self.target = target
    self.field = field
    self.snippet = snippet
    self.locator = locator
  }

  public enum Target: Hashable, Codable, Sendable {
    case mentor(EntityID)
    case lesson(LessonRef)
    case item(EntityID)
    case note(EntityID, on: ContentRef)
  }

  public enum Field: String, Hashable, Codable, Sendable {
    case name
    case title
    case body
    case note
  }
}
