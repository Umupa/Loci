import Foundation
import GRDB
import LociModel

extension StoreDatabase {
  /// Finds items by title and text, and notes by anything written in them. Every word must match; Chinese, Japanese and Korean match as substrings, and the last Latin
  /// word as a prefix. Titles rank above text.
  public func search(_ text: String, limit: Int = 50) throws -> [SearchHit] {
    guard let query = SearchText.query(text) else { return [] }
    let terms = text.split(whereSeparator: \.isWhitespace).map(String.init)
    let rows = try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT target, field, original, locator FROM search WHERE search MATCH ?
          ORDER BY bm25(search) * (CASE field WHEN 'body' THEN 1.0 WHEN 'note' THEN 1.5 ELSE 3.0 END)
          LIMIT ?
          """,
        arguments: [query, limit])
    }
    return rows.compactMap { row in
      let original: String = row["original"]
      let fieldName: String = row["field"]
      let locatorText: String? = row["locator"]
      let noteLocator = locatorText.flatMap(Locator.init)
      guard let field = SearchHit.Field(rawValue: fieldName), let target = Self.target(row["target"], noteLocator)
      else { return nil }
      let match = Self.firstMatch(of: terms, in: original)
      var locator = noteLocator
      if field == .body, case .item(let item) = target, let match, let quote = Self.quote(match, in: original) {
        locator = .item(item, .quote(quote))
      }
      return SearchHit(
        target: target, field: field, snippet: Self.snippet(around: match, in: original), locator: locator)
    }
  }

  private static func target(_ text: String, _ noteLocator: Locator?) -> SearchHit.Target? {
    if text.hasPrefix("note/") {
      guard let id = EntityID(canonical: String(text.dropFirst(5))), let noteLocator else { return nil }
      return .note(id, on: noteLocator.content)
    }
    switch ContentKey.content(text) {
    case .item(let item): return .item(item)
    case nil: return nil
    }
  }

  private static let context = 40

  /// The first place any search term appears, widened to the end of a word it starts.
  private static func firstMatch(of terms: [String], in text: String) -> Range<String.Index>? {
    let found = terms.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
    guard var match = found.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
    while match.upperBound < text.endIndex, text[match.upperBound].isASCII, text[match.upperBound].isLetter {
      match = match.lowerBound..<text.index(after: match.upperBound)
    }
    return match
  }

  private static func snippet(around match: Range<String.Index>?, in text: String) -> String {
    let lower = match.map {
      text.index($0.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
    }
    let start = lower ?? text.startIndex
    let end =
      match.map { text.index($0.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex }
      ?? (text.index(text.startIndex, offsetBy: context * 2, limitedBy: text.endIndex) ?? text.endIndex)
    let body = text[start..<end].split(whereSeparator: \.isNewline).joined(separator: " ")
    return (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
  }

  private static func quote(_ match: Range<String.Index>, in text: String) -> TextQuote? {
    let before = String(text[..<match.lowerBound].suffix(32))
    let after = String(text[match.upperBound...].prefix(32))
    return try? TextQuote(
      String(text[match]), before: before.isEmpty ? nil : before, after: after.isEmpty ? nil : after)
  }
}
