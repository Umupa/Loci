/// A place in a book: one character of the text in one chapter, and how far into the whole book that is.
///
/// Written `chapter=<n>&node=<i>.<j>…&char=<n>&share=<0–10000>`. The node is the path of child indexes from the
/// chapter's `body` to a text node, and the character is an offset into that node, so the place survives any
/// change of font, size or window. The share is how much of the book lies before it, kept to a hundredth of a
/// percent, for showing progress without opening the book.
public struct BookSpot: Hashable, Sendable {
  /// Counted from 0, in reading order.
  public let chapter: Int
  public let node: [Int]
  public let character: Int
  public let share: Fraction

  public init(chapter: Int, node: [Int], character: Int, share: Fraction) throws {
    guard chapter >= 0, character >= 0 else { throw ModelError("chapters and characters are counted from 0") }
    guard !node.isEmpty, node.allSatisfy({ $0 >= 0 }) else { throw ModelError("not a path of child indexes") }
    self.chapter = chapter
    self.node = node
    self.character = character
    self.share = Fraction((share.value * Self.scale).rounded() / Self.scale)
  }

  static let scale = 10_000.0

  init?(chapter text: String, taking fragment: inout Fragment) {
    guard let chapter = Int(digits: text),
      let node = fragment.take("node").flatMap(Self.path),
      let character = fragment.take("char").flatMap({ Int(digits: $0) }),
      let share = fragment.take("share").flatMap({ Int(digits: $0) }), Double(share) <= Self.scale,
      let spot = try? BookSpot(
        chapter: chapter, node: node, character: character, share: Fraction(Double(share) / Self.scale))
    else { return nil }
    self = spot
  }

  var fragment: String {
    Fragment.join([
      ("chapter", String(chapter)), ("node", node.map(String.init).joined(separator: ".")),
      ("char", String(character)), ("share", String(Int((share.value * Self.scale).rounded()))),
    ])
  }

  private static func path(_ text: String) -> [Int]? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int(digits: String($0)) }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
    return parts.compactMap { $0 }
  }
}
