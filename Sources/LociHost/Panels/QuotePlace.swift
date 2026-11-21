import Foundation
import LociModel

/// Where a quote the reader took falls in the item's Markdown. The reader quotes the text as it shows it:
/// list bullets, link text without its address, code without its backticks. When the exact words are not in
/// the Markdown, the quote is looked for by its letters and digits alone.
enum QuotePlace {
  /// Fewer letters than this could be found in too many places; the words after the quote are added.
  static let shortest = 12

  /// A quote with nothing before it was taken at the very top, over the title and byline the reader adds:
  /// it is the start, wherever the same words come again.
  static func start(of quote: TextQuote, in markdown: String) -> String.Index? {
    if quote.before == nil { return markdown.startIndex }
    if let range = quote.range(in: markdown) { return range.lowerBound }
    let text = Letters(markdown)
    var key = Letters(quote.text).scalars
    if key.count < shortest { key = Letters(quote.text + (quote.after ?? "")).scalars }
    guard key.count >= shortest else { return nil }
    let before = Letters(quote.before ?? "").scalars.suffix(shortest)
    let found = text.occurrences(of: key)
    let fitting = found.first { at in at >= before.count && text.scalars[(at - before.count)..<at].elementsEqual(before)
    }
    return (fitting ?? found.first).map { text.places[$0] }
  }

  /// A text's letters and digits, lowercased, each with where it is in the text.
  private struct Letters {
    var scalars: [Unicode.Scalar] = []
    var places: [String.Index] = []

    init(_ text: String) {
      var index = text.unicodeScalars.startIndex
      while index < text.unicodeScalars.endIndex {
        let scalar = text.unicodeScalars[index]
        if CharacterSet.alphanumerics.contains(scalar) {
          scalars += String(scalar).lowercased().unicodeScalars
          places += Array(repeating: index, count: String(scalar).lowercased().unicodeScalars.count)
        }
        index = text.unicodeScalars.index(after: index)
      }
    }

    func occurrences(of key: [Unicode.Scalar]) -> [Int] {
      guard !key.isEmpty, key.count <= scalars.count else { return [] }
      return (0...(scalars.count - key.count)).filter { at in
        scalars[at] == key[0] && scalars[at..<(at + key.count)].elementsEqual(key)
      }
    }
  }
}
