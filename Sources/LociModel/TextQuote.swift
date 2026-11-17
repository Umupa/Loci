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
