import Foundation

/// Makes Chinese, Japanese and Korean text searchable by any run of characters.
///
/// SQLite's tokenizer treats an unbroken run of Han characters as one word, so 「调度」 would never find
/// 「调度器的基本问题」. Every such character becomes a word of its own, both in the index and in the
/// query, and a query term is matched as a phrase: adjacent characters in order, which is a substring
/// search. Latin words stay whole, and the last one also matches as a prefix.
enum SearchText {
  static func indexed(_ text: String) -> String {
    var spaced = ""
    spaced.reserveCapacity(text.utf8.count)
    for scalar in text.unicodeScalars {
      if isCJK(scalar) {
        spaced.unicodeScalars.append(" ")
        spaced.unicodeScalars.append(scalar)
        spaced.unicodeScalars.append(" ")
      } else {
        spaced.unicodeScalars.append(scalar)
      }
    }
    return spaced
  }

  /// An FTS5 query that finds every term, or `nil` when the text has nothing to search for.
  static func query(_ text: String) -> String? {
    let terms = terms(text)
    let phrases = terms.enumerated().map { index, tokens in
      let phrase = "\"\(tokens.joined(separator: " "))\""
      let isLast = index == terms.count - 1
      return isLast && !(tokens.last.map(isCJKWord) ?? true) ? phrase + "*" : phrase
    }
    return phrases.isEmpty ? nil : phrases.joined(separator: " ")
  }

  /// The words of each whitespace-separated term, as the index sees them.
  static func terms(_ text: String) -> [[String]] {
    text.split(whereSeparator: \.isWhitespace).compactMap { term in
      let tokens = indexed(String(term)).split { !($0.isLetter || $0.isNumber) }.map(String.init)
      return tokens.isEmpty ? nil : tokens
    }
  }

  private static func isCJKWord(_ word: String) -> Bool {
    word.unicodeScalars.allSatisfy(isCJK)
  }

  private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
      true
    default:
      false
    }
  }
}
