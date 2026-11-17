/// A transcript in another language, one line per segment in the same order; the contents of
/// `translations/<language>.json`.
public struct Translation: Hashable, Codable, Sendable {
  /// A BCP 47 tag.
  public let language: String
  public let lines: [String]

  public init(language: String, lines: [String]) throws {
    self.language = try language.requiringText("language")
    self.lines = lines
  }

  /// Whether this was made from a transcript shaped like `transcript`. A transcript recognized again may
  /// not be, and its old translation must not be shown against it.
  public func fits(_ transcript: Transcript) -> Bool {
    lines.count == transcript.segments.count
  }
}
