import Foundation

/// A passage of text, found by its exact words and optionally the words just before and after it.
///
/// Quoting instead of counting characters lets a note find its place again after the text is fetched anew
/// or revised; when the quote is gone, the note is marked lost rather than pointing somewhere else.
public struct TextQuote: Hashable, Sendable {
  public let text: String
  public let before: String?
  public let after: String?

  public init(_ text: String, before: String? = nil, after: String? = nil) throws {
    self.text = try text.requiringText("quote")
    if before?.isEmpty == true || after?.isEmpty == true { throw ModelError("context around a quote is empty") }
    self.before = before
    self.after = after
  }

  init?(taking fragment: inout Fragment) {
    guard let text = fragment.take("quote"),
      let quote = try? TextQuote(text, before: fragment.take("pre"), after: fragment.take("post"))
    else { return nil }
    self = quote
  }

  var fragment: String {
    Fragment.join([("quote", text), ("pre", before), ("post", after)])
  }
}

extension TextQuote {
  /// How many characters of context a new quote keeps on each side.
  public static let contextLength = 24

  /// Quotes part of `text`, with the words just around it so the quote can be told apart from the same
  /// words elsewhere. Throws when the part is only whitespace.
  public init(quoting range: Range<String.Index>, in text: String, context: Int = contextLength) throws {
    let before = String(text[..<range.lowerBound].suffix(context))
    let after = String(text[range.upperBound...].prefix(context))
    try self.init(String(text[range]), before: before.isEmpty ? nil : before, after: after.isEmpty ? nil : after)
  }

  /// Where the quote is in `text`, or `nil` when its words are no longer there.
  ///
  /// Where the same words appear more than once, the place whose surrounding words match the quote's
  /// context wins; between equally good places, the first.
  public func range(in text: String) -> Range<String.Index>? {
    var best: (range: Range<String.Index>, score: Int)?
    var start = text.startIndex
    while start < text.endIndex, let found = text.range(of: self.text, options: .literal, range: start..<text.endIndex)
    {
      let score = contextScore(of: found, in: text)
      if score > best?.score ?? -1 { best = (found, score) }
      if score == 2 { break }
      start = text.index(after: found.lowerBound)
    }
    return best?.range
  }

  private func contextScore(of range: Range<String.Index>, in text: String) -> Int {
    let beforeMatches = before.map { text[..<range.lowerBound].hasSuffix($0) } ?? true
    let afterMatches = after.map { text[range.upperBound...].hasPrefix($0) } ?? true
    return (beforeMatches ? 1 : 0) + (afterMatches ? 1 : 0)
  }
}
