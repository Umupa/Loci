import Foundation
import LociModel

/// How far into an item a reading position is, and how long the rest takes: a video or podcast by its
/// length, an article at an ordinary reading pace.
enum ReadingProgress {
  /// Chinese, Japanese and Korean characters read in a minute.
  static let charactersPerMinute = 400
  /// Words of other languages read in a minute.
  static let wordsPerMinute = 230

  /// `nil` when it cannot be told: no length yet, a quote no longer in the text, a page of a PDF.
  static func of(_ position: Locator, in item: Item, text: () -> String?) -> ReadingNow? {
    guard case .item(_, let anchor) = position else { return nil }
    switch (anchor, item.kind) {
    case (.time(let span), .video(let duration?)), (.time(let span), .audio(let duration?)):
      let at = min(span.start, duration)
      let left = Int(((duration - at) / .seconds(60)).rounded(.up))
      return ReadingNow(item: item, progress: at / duration, minutesLeft: max(left, 1))
    case (.quote(let quote), .article), (.quote(let quote), .paper):
      guard let text = text(), !text.isEmpty, let start = QuotePlace.start(of: quote, in: text) else { return nil }
      let read = text.distance(from: text.startIndex, to: start)
      let rest = text[start...]
      return ReadingNow(
        item: item, progress: Double(read) / Double(text.count), minutesLeft: max(minutes(toRead: rest), 1))
    default:
      return nil
    }
  }

  static func minutes(toRead text: Substring) -> Int {
    var characters = 0
    var words = 0
    var inWord = false
    for scalar in text.unicodeScalars {
      if isIdeograph(scalar) {
        characters += 1
        inWord = false
      } else if CharacterSet.alphanumerics.contains(scalar) {
        if !inWord { words += 1 }
        inWord = true
      } else {
        inWord = false
      }
    }
    let minutes = Double(characters) / Double(charactersPerMinute) + Double(words) / Double(wordsPerMinute)
    return Int(minutes.rounded(.up))
  }

  private static func isIdeograph(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF: true
    default: false
    }
  }
}
